"""
v2 Day View endpoint: GET /api/days/{day}/view

Returns a single payload containing everything the home screen needs,
with mode = today | past | future.
"""
import asyncio
from datetime import date as date_type, datetime, timedelta, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pymongo.database import Database

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
    }


def _build_motivation(targets: dict, day_of_week: int) -> dict:
    """Deterministic motivational card for future days. No AI."""
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

    return {
        "headline": f"{day_name}: make it count.",
        "message": "Your targets are set. Start strong and the rest of the day follows.",
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
            "motivation": _build_motivation(targets, day.weekday()),
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
        "motivation": None,
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
         "$set": {"verdict_status": "pending", "updated_at": datetime.now(timezone.utc)}},
        upsert=True,
    )
    background_tasks.add_task(generate_verdict_background, database, user_id, day_key)
    return {"detail": "Analysis started.", "verdict_status": "pending"}
