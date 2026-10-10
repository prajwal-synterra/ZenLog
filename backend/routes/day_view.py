"""
v2 Day View endpoint: GET /api/days/{day}/view

Returns a single payload containing everything the home screen needs,
with mode = today | past | future.
"""
import asyncio
from datetime import date as date_type, datetime, timedelta, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pymongo.database import Database

from backend.core.insight_hash import input_hash
from backend.models.analytics import DayVerdictGenerateRequest, DayVerdictResponse
from backend.models.log import IST
from backend.routes.dependencies import get_auth_context, get_database
from backend.services.close_service import (
    close_day_sync,
    ensure_past_days_closed,
    generate_verdict_background,
    get_user_targets_snapshot,
)
from backend.services.progress_engine import (
    compute_day_score,
    compute_day_totals,
    compute_progress,
)
from backend.services.quote_service import get_or_create_daily_quote


router = APIRouter(prefix="/api/days", tags=["day_view"])


def _logical_today() -> date_type:
    """IST date, 4 AM cutoff."""
    now_ist = datetime.now(IST)
    if now_ist.hour < 4:
        return (now_ist - timedelta(hours=4)).date()
    return now_ist.date()


def _serialize_entry(doc: dict) -> dict:
    local_ts = doc["timestamp"].astimezone(IST)
    return {
        "id": str(doc["_id"]),
        "time_display": local_ts.strftime("%I:%M %p"),
        "text": doc["text"],
        "extraction_status": doc.get("extraction_status", "done"),
        "extraction_error": doc.get("extraction_error"),
        "extracted": doc.get("extracted"),
        "overrides": doc.get("overrides") or {},
        "created_at": doc.get("created_at"),
        "updated_at": doc.get("updated_at"),
        "client_id": doc.get("client_id"),
    }



def _build_motivation(targets: dict, day_of_week: int, quote_data: dict | None = None) -> dict:
    """Motivational card for future days with 24h cached quote."""
    days_map = {0: "Monday", 1: "Tuesday", 2: "Wednesday", 3: "Thursday",
                4: "Friday", 5: "Saturday", 6: "Sunday"}
    day_name = days_map.get(day_of_week, "Today")
    goal = targets.get("goal", "muscle_gain")
    protein = targets.get("protein_g", 0)
    water = targets.get("water_ml", 3000)
    calories = targets.get("calories_kcal")

    goal_line = {
        "muscle_gain": f"Front-load ~{round((protein or 0) * 0.35)}g protein at breakfast.",
        "fat_loss": f"Stay under {calories or '—'} kcal. Prioritize volume foods.",
        "maintenance": "Keep today balanced. Match yesterday's wins.",
        "mindfulness": "Track your habits and mood entries. Quality > quantity.",
    }.get(goal, "Stay consistent with your targets.")

    quote_text = quote_data.get("quote") if quote_data else None
    author = quote_data.get("author") if quote_data else None
    message = f"\"{quote_text}\" — {author}" if quote_text else "Your targets are set. Start strong and the rest of the day follows."

    return {
        "headline": f"{day_name}: make it count.",
        "message": message,
        "quote": quote_text,
        "author": author,
        "focus_points": [goal_line, f"Drink {water}ml water throughout the day."],
        "plan": {
            "protein_g": protein,
            "calories_kcal": calories,
            "water_ml": water,
        },
        "tone": "steady",
    }


@router.get("/{day}/view")
def get_day_view(
    day: date_type,
    background_tasks: BackgroundTasks,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user = auth_context["user"]
    user_id = user["user_id"]
    day_key = day.isoformat()
    today = _logical_today()

    # Get 24-hour motivational quote for this day (cached in DB for 24h, or RapidAPI, or fallback)
    daily_quote = get_or_create_daily_quote(database, user_id, day_key)

    # Lazy-close any open past days (cheap, idempotent)
    if day < today:
        ensure_past_days_closed(database, user_id)

    # Determine mode
    if day > today:
        mode = "future"
    elif day == today:
        mode = "today"
    else:
        mode = "past"

    # For future: no data needed, return motivational card
    if mode == "future":
        targets = get_user_targets_snapshot(user)
        return {
            "date": day_key,
            "mode": "future",
            "is_closed": False,
            "pending_count": 0,
            "failed_count": 0,
            "logs": [],
            "totals": {"protein_g": 0, "calories_kcal": 0, "hydration_ml": 0, "workout_done": False, "workout_mins": 0},
            "targets": targets,
            "progress": None,
            "score": None,
            "rating": None,
            "verdict": None,
            "verdict_status": "none",
            "motivation": _build_motivation(targets, day.weekday(), daily_quote),
            "quote": daily_quote,
        }

    # Load all entries for this day
    entries_raw = list(database["daily_logs"].find(
        {"user_id": user_id, "date": day_key}
    ).sort("timestamp", 1))

    entries = [_serialize_entry(e) for e in entries_raw]
    pending_count = sum(1 for e in entries_raw if e.get("extraction_status") == "pending")
    failed_count = sum(1 for e in entries_raw if e.get("extraction_status") == "failed")

    # Compute totals and progress
    totals = compute_day_totals(entries_raw)
    targets = get_user_targets_snapshot(user)

    # Calculate weekly workouts for the week containing this day
    week_start = day - timedelta(days=day.weekday())
    week_end = week_start + timedelta(days=6)
    workout_dates = set(database["daily_logs"].distinct(
        "date",
        {
            "user_id": user_id,
            "date": {"$gte": week_start.isoformat(), "$lte": week_end.isoformat()},
            "extraction_status": "done",
            "extracted.workout": {"$ne": None},
        }
    ))
    if totals.get("workout_done"):
        workout_dates.add(day_key)
    week_done = len(workout_dates)

    now_ist = datetime.now(IST) if mode == "today" else None
    progress = compute_progress(totals, targets, mode=mode, now_ist=now_ist, week_done=week_done)

    # Load or create day doc
    day_doc = database["days"].find_one({"user_id": user_id, "date": day_key})

    # For past days: ensure closed
    verdict = None
    verdict_status = "none"
    score = None
    rating = None

    if mode == "past":
        if not day_doc or not day_doc.get("closed"):
            # Trigger close inline (fast — just deterministic scoring)
            day_doc = close_day_sync(database, user_id, day_key)
            if day_doc and day_doc.get("verdict_status") == "pending":
                # Enqueue Gemini verdict in background
                background_tasks.add_task(generate_verdict_background, database, user_id, day_key)

        if day_doc:
            score = day_doc.get("score")
            rating = day_doc.get("rating")
            verdict_status = day_doc.get("verdict_status", "none")
            verdict = day_doc.get("verdict")
    else:
        # Today: live partial score
        if len(entries_raw) >= 2:
            score, rating = compute_day_score(totals, targets, entries_raw)
        if day_doc:
            verdict_status = day_doc.get("verdict_status", "none")
            verdict = day_doc.get("verdict")

    return {
        "date": day_key,
        "mode": mode,
        "is_closed": bool(day_doc and day_doc.get("closed")) if mode == "past" else False,
        "pending_count": pending_count,
        "failed_count": failed_count,
        "logs": entries,
        "totals": totals,
        "targets": targets,
        "progress": progress,
        "score": score,
        "rating": rating,
        "verdict": verdict,
        "verdict_status": verdict_status,
        "data_changed_since_review": bool(day_doc and day_doc.get("data_changed_since_review", False)),
        "motivation": None,
        "quote": daily_quote,
    }


@router.post("/{day}/analyze")
def analyze_day(
    day: date_type,
    background_tasks: BackgroundTasks,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """On-demand: regenerate/generate the AI verdict for a day. Cap: 10/day."""
    user_id = auth_context["user"]["user_id"]
    day_key = day.isoformat()

    day_doc = database["days"].find_one({"user_id": user_id, "date": day_key})
    count = (day_doc or {}).get("analysis_count_today", 0)
    if count >= 10:
        raise HTTPException(status_code=429, detail="Analysis limit reached for this day (10/day).")

    database["days"].update_one(
        {"user_id": user_id, "date": day_key},
        {"$inc": {"analysis_count_today": 1},
         "$set": {
             "verdict_status": "pending",
             "data_changed_since_review": False,
             "updated_at": datetime.now(timezone.utc),
         }},
        upsert=True,
    )
    background_tasks.add_task(generate_verdict_background, database, user_id, day_key)
    return {"detail": "Analysis started.", "verdict_status": "pending"}


def _get_day_verdict_hash(database: Database, user_id: str, day_key: str) -> tuple[str, dict, dict]:
    user = database["users"].find_one({"user_id": user_id}, {"_id": 0, "phone_number": 0}) or {}
    targets = get_user_targets_snapshot(user)
    entries = list(database["daily_logs"].find({"user_id": user_id, "date": day_key}).sort("timestamp", 1))
    totals = compute_day_totals(entries)
    day_row = {
        "logical_date": day_key,
        "protein_g": totals.get("protein_g", 0.0),
        "calories": totals.get("calories_kcal", 0.0),
        "water_ml": totals.get("hydration_ml", 0.0),
        "workout": totals.get("workout_done", False),
        "sleep_min": 0,
    }
    computed_hash = input_hash([day_row], targets, targets.get("goal", "muscle_gain"), "verdict-v2")
    return computed_hash, targets, totals


@router.get("/{day}/verdict", response_model=DayVerdictResponse)
def get_day_verdict(
    day: date_type,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Module 5: Returns cached day verdict with status: fresh | stale | none.
    NEVER calls Gemini.
    """
    user_id = auth_context["user"]["user_id"]
    day_key = day.isoformat()
    current_hash, _, _ = _get_day_verdict_hash(database, user_id, day_key)

    day_doc = database["days"].find_one({"user_id": user_id, "date": day_key})
    verdict = (day_doc or {}).get("verdict")
    cached_hash = (day_doc or {}).get("input_hash")
    data_changed = (day_doc or {}).get("data_changed_since_review", False)

    if not verdict:
        # Check insight_cache collection fallback
        cached = database["insight_cache"].find_one({
            "user_id": user_id,
            "kind": "day",
            "range_start": day_key,
            "range_end": day_key,
        })
        if cached and cached.get("report"):
            verdict = cached["report"]
            cached_hash = cached.get("input_hash")

    if not verdict or verdict.get("status") not in ("done", "failed"):
        return DayVerdictResponse(
            status="none",
            day=day_key,
            verdict=None,
            generated_at=None,
            input_hash=None,
            current_hash=current_hash,
            can_generate=True,
        )

    is_fresh = bool(cached_hash and cached_hash == current_hash and not data_changed)
    status_label = "fresh" if is_fresh else "stale"

    gen_at = verdict.get("generated_at")
    return DayVerdictResponse(
        status=status_label,
        day=day_key,
        verdict=verdict,
        generated_at=gen_at,
        input_hash=cached_hash,
        current_hash=current_hash,
        can_generate=True,
    )


@router.post("/{day}/verdict", response_model=DayVerdictResponse)
async def generate_day_verdict(
    day: date_type,
    payload: DayVerdictGenerateRequest = DayVerdictGenerateRequest(),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Module 5: Generates / updates the AI day verdict.
    - If hash matches and force is False and data hasn't changed, returns cached without Gemini.
    - Enforces 10-minute cooldown on regeneration unless force is True.
    - Max 10 calls per day.
    """
    user_id = auth_context["user"]["user_id"]
    day_key = day.isoformat()
    current_hash, targets, totals = _get_day_verdict_hash(database, user_id, day_key)
    now = datetime.now(timezone.utc)

    day_doc = database["days"].find_one({"user_id": user_id, "date": day_key})
    if not day_doc:
        day_doc = close_day_sync(database, user_id, day_key)
        if not day_doc:
            database["days"].update_one(
                {"user_id": user_id, "date": day_key},
                {"$set": {
                    "targets_snapshot": targets,
                    "updated_at": now,
                }},
                upsert=True,
            )
            day_doc = database["days"].find_one({"user_id": user_id, "date": day_key})

    verdict = (day_doc or {}).get("verdict")
    cached_hash = (day_doc or {}).get("input_hash")
    data_changed = (day_doc or {}).get("data_changed_since_review", False)

    # 1. Reuse cache if hash matches and force is False and not marked modified
    if verdict and verdict.get("status") == "done" and not payload.force:
        if cached_hash == current_hash and not data_changed:
            return DayVerdictResponse(
                status="fresh",
                day=day_key,
                verdict=verdict,
                generated_at=verdict.get("generated_at"),
                input_hash=cached_hash,
                current_hash=current_hash,
                can_generate=True,
            )

        # 2. Check 10-minute cooldown if recent verdict exists
        last_gen = verdict.get("generated_at")
        if last_gen:
            if isinstance(last_gen, str):
                try:
                    last_gen = datetime.fromisoformat(last_gen)
                except Exception:
                    last_gen = None
            if last_gen and last_gen.tzinfo is None:
                last_gen = last_gen.replace(tzinfo=timezone.utc)
            if last_gen:
                elapsed = (now - last_gen).total_seconds()
                if elapsed < 600:
                    return DayVerdictResponse(
                        status="stale",
                        day=day_key,
                        verdict=verdict,
                        generated_at=last_gen,
                        input_hash=cached_hash,
                        current_hash=current_hash,
                        can_generate=True,
                        warning="Regeneration cooldown active (10 minutes). Showing previous review.",
                    )

    # Check daily analysis cap
    count = (day_doc or {}).get("analysis_count_today", 0)
    if count >= 10:
        raise HTTPException(status_code=429, detail="Analysis limit reached for this day (10/day).")

    database["days"].update_one(
        {"user_id": user_id, "date": day_key},
        {"$inc": {"analysis_count_today": 1},
         "$set": {
             "verdict_status": "pending",
             "data_changed_since_review": False,
             "updated_at": now,
         }},
        upsert=True,
    )

    await generate_verdict_background(database, user_id, day_key)

    updated_day = database["days"].find_one({"user_id": user_id, "date": day_key}) or {}
    new_verdict = updated_day.get("verdict")
    status_label = "fresh" if (new_verdict and new_verdict.get("status") == "done") else "stale"

    return DayVerdictResponse(
        status=status_label,
        day=day_key,
        verdict=new_verdict,
        generated_at=new_verdict.get("generated_at") if new_verdict else now,
        input_hash=updated_day.get("input_hash") or current_hash,
        current_hash=current_hash,
        can_generate=True,
    )
