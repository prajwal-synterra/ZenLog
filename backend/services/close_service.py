"""
Lazy close + Gemini verdict for ZenLog v2.

close_day():  deterministic close. Always fast.
generate_verdict():  one Gemini call for narrative. Run in background.
"""
import json
from datetime import date as date_type, datetime, timedelta, timezone

from backend.models.log import IST
from backend.services.progress_engine import compute_day_score, compute_day_totals


def _calculate_default_calories(user: dict) -> float:
    cal = user.get("daily_calorie_target")
    if cal and float(cal) > 0:
        return float(cal)
    bw = float(user.get("body_weight_kg") or 60.0)
    goal = user.get("goal", "muscle_gain")
    if goal == "muscle_gain":
        target = round(bw * 35.0)
    elif goal == "fat_loss":
        target = round(bw * 25.0)
    else:
        target = round(bw * 30.0)
    return max(1500.0, min(3500.0, float(target)))


def _get_targets(user: dict) -> dict:
    return {
        "protein_g": user.get("daily_protein_target_g") or 0,
        "calories_kcal": _calculate_default_calories(user),
        "water_ml": user.get("daily_water_target_ml") or 3000,
        "weekly_workout_target": user.get("weekly_workout_target") or 3,
        "goal": user.get("goal", "muscle_gain"),
    }


def get_user_targets_snapshot(user: dict) -> dict:
    """Return a snapshot of targets to freeze at close time."""
    return {
        "protein_g": user.get("daily_protein_target_g"),
        "calories_kcal": _calculate_default_calories(user),
        "water_ml": user.get("daily_water_target_ml", 3000),
        "weekly_workout_target": user.get("weekly_workout_target", 3),
        "goal": user.get("goal", "muscle_gain"),
    }


def close_day_sync(database, user_id: str, day_key: str):
    """
    Idempotent synchronous close. Safe to call multiple times.
    Writes score, rating, targets_snapshot to days collection.
    Returns the days doc.
    """
    now = datetime.now(timezone.utc)

    # Atomic claim
    result = database["days"].find_one_and_update(
        {"user_id": user_id, "date": day_key, "closed": {"$ne": True}, "closing": {"$ne": True}},
        {"$set": {"closing": True, "updated_at": now}},
        upsert=False,
        return_document=False,
    )
    # If already closed or being closed by another caller, return current doc
    if result is None:
        doc = database["days"].find_one({"user_id": user_id, "date": day_key})
        return doc

    # Load user for target snapshot
    user = database["users"].find_one({"user_id": user_id}, {"_id": 0, "phone_number": 0})
    targets_snapshot = get_user_targets_snapshot(user or {})

    # Load all done entries
    entries = list(database["daily_logs"].find(
        {"user_id": user_id, "date": day_key},
    ).sort("timestamp", 1))

    totals = compute_day_totals(entries)
    score, rating = compute_day_score(totals, targets_snapshot, entries)

    database["days"].update_one(
        {"user_id": user_id, "date": day_key},
        {"$set": {
            "closed": True,
            "closed_at": now,
            "closing": False,
            "score": score,
            "rating": rating,
            "targets_snapshot": targets_snapshot,
            "verdict_status": "pending",
            "updated_at": now,
        }},
        upsert=True,
    )
    return database["days"].find_one({"user_id": user_id, "date": day_key})


def ensure_past_days_closed(database, user_id: str):
    """Trigger lazy close for all open past days. Called on app-facing requests."""
    today_key = datetime.now(IST).date().isoformat()

    # Days docs that are open
    open_days = set(database["days"].distinct(
        "date",
        {"user_id": user_id, "closed": {"$ne": True}, "date": {"$lt": today_key}},
    ))
    # Dates that have logs but no day doc yet
    days_with_logs = set(database["daily_logs"].distinct(
        "date",
        {"user_id": user_id, "date": {"$lt": today_key}},
    ))
    all_days = open_days | days_with_logs

    for d in sorted(all_days):
        try:
            close_day_sync(database, user_id, d)
        except Exception:
            pass  # Never block the main request for a close failure


async def generate_verdict_background(database, user_id: str, day_key: str):
    """
    Run Gemini once to produce the narrative verdict for a closed day.
    Stores result in days.verdict. Falls back to templated text on failure.
    """
    import asyncio
    from backend.ai.gemini_client import generate_structured
    from pydantic import BaseModel, Field

    class VerdictAI(BaseModel):
        headline: str
        verdict_summary: str
        went_well: list[str] = Field(default_factory=list)
        hurt_the_goal: list[str] = Field(default_factory=list)
        fixes_for_tomorrow: list[str] = Field(default_factory=list)
        coaching_note: str = ""

    loop = asyncio.get_event_loop()

    def _load():
        day = database["days"].find_one({"user_id": user_id, "date": day_key})
        user = database["users"].find_one({"user_id": user_id}, {"_id": 0, "phone_number": 0})
        entries = list(database["daily_logs"].find(
            {"user_id": user_id, "date": day_key}
        ).sort("timestamp", 1))
        return day, user, entries

    day, user, entries = await loop.run_in_executor(None, _load)
    if not day:
        return

    from backend.services.progress_engine import compute_day_totals, compute_progress
    targets = {
        "protein_g": (day.get("targets_snapshot") or {}).get("protein_g", 0),
        "calories_kcal": (day.get("targets_snapshot") or {}).get("calories_kcal"),
        "water_ml": (day.get("targets_snapshot") or {}).get("water_ml", 3000),
        "weekly_workout_target": (day.get("targets_snapshot") or {}).get("weekly_workout_target", 3),
        "goal": (day.get("targets_snapshot") or {}).get("goal", "muscle_gain"),
    }
    totals = compute_day_totals(entries)
    progress = compute_progress(totals, targets, mode="past")

    entry_summaries = [
        {
            "time": e["timestamp"].astimezone(IST).strftime("%H:%M"),
            "text": e["text"],
            "extracted": e.get("extracted"),
        }
        for e in entries if e.get("extraction_status") == "done"
    ]

    payload = {
        "goal": targets["goal"],
        "targets": targets,
        "totals": totals,
        "score": day.get("score"),
        "rating": day.get("rating"),
        "metric_statuses": {
            "protein": progress["protein"]["status"],
            "water": progress["water"]["status"],
            "calories": progress["calories"]["status"],
        },
        "entries": entry_summaries,
    }

    prompt = (
        "You are a personal health coach writing a day-end review.\n"
        "Rules:\n"
        "- Use ONLY the supplied data. Do not invent foods, quantities, or numbers.\n"
        "- The 'rating' and 'score' are final; do not contradict them. Explain them.\n"
        "- Be direct. If the day was poor, say so and say why. No empty praise.\n"
        "- Max 3 items in went_well and hurt_the_goal. Max 3 fixes.\n"
        "- No medical diagnosis, no supplement or drug advice.\n"
        "- Return JSON only. No markdown fences.\n\n"
        f"Data:\n{json.dumps(payload, ensure_ascii=False, default=str)}"
    )

    try:
        result, model_name = await loop.run_in_executor(
            None, lambda: generate_structured(VerdictAI, prompt)
        )
        # Cap list lengths
        ai_data = result.model_dump(mode="json")
        ai_data["went_well"] = ai_data["went_well"][:3]
        ai_data["hurt_the_goal"] = ai_data["hurt_the_goal"][:3]
        ai_data["fixes_for_tomorrow"] = ai_data["fixes_for_tomorrow"][:3]

        verdict = {
            "score": day.get("score"),
            "rating": day.get("rating"),
            "ai": ai_data,
            "generated_at": datetime.now(timezone.utc),
            "model": model_name,
            "status": "done",
        }

    except Exception as e:
        # Templated fallback
        score = day.get("score", 0)
        rating = day.get("rating", "ok")
        verdict = {
            "score": score,
            "rating": rating,
            "ai": {
                "headline": f"Day review: {rating.upper()} ({score}/100)",
                "verdict_summary": (
                    f"Protein: {totals['protein_g']}g / {targets['protein_g']}g. "
                    f"Water: {totals['hydration_ml']}ml. "
                    f"Workout: {'done' if totals['workout_done'] else 'none'}."
                ),
                "went_well": [],
                "hurt_the_goal": [],
                "fixes_for_tomorrow": [],
                "coaching_note": "Analysis unavailable — will retry next time.",
            },
            "generated_at": datetime.now(timezone.utc),
            "model": "fallback",
            "status": "failed",
            "error": str(e)[:200],
        }

    await loop.run_in_executor(
        None,
        lambda: database["days"].update_one(
            {"user_id": user_id, "date": day_key},
            {"$set": {"verdict": verdict, "verdict_status": verdict["status"],
                       "updated_at": datetime.now(timezone.utc)}},
        ),
    )
