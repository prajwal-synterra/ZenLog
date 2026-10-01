"""
Per-entry extraction background task for ZenLog v2.

Flow:
  POST /api/logs  →  save (extraction_status=pending)  →  enqueue extract_log()
  extract_log()   →  Gemini on THIS entry only         →  update log with extracted + status=done
  sweeper()       →  re-enqueues any stuck pending logs on startup / every 5 min
"""
import asyncio
import hashlib
import json
from datetime import datetime, timedelta, timezone

from backend.ai.gemini_client import generate_structured
from backend.models.entry_extraction import EntryExtraction
from backend.models.log import IST

ENTRY_EXTRACTION_PROMPT_VERSION = "entry-extraction-v1"

# Clamp limits (out-of-range → cap + lower confidence)
MAX_PROTEIN_PER_ITEM_G = 150.0
MAX_CALORIES_PER_ITEM = 2500.0
MAX_HYDRATION_PER_LOG_ML = 3000
MAX_WORKOUT_DURATION_MINS = 300


def _compute_text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:32]


def _validate_and_recompute(result: EntryExtraction, text: str) -> dict:
    """
    Validate, clamp absurd values, and recompute sums from items.
    Returns a plain dict suitable for MongoDB storage.
    """
    raw = result.model_dump(mode="json")

    # --- Nutrition: recompute protein/calories from items ---
    nutrition = raw.get("nutrition")
    if nutrition and nutrition.get("items"):
        # Check if the log even contains food-related words before trusting nutrition
        food_words = {"ate", "eat", "meal", "breakfast", "lunch", "dinner", "snack",
                      "drank", "drink", "food", "cup", "plate", "bowl", "glass",
                      "roti", "rice", "egg", "protein", "chicken", "dal", "sabzi", "curry",
                      "banana", "apple", "milk", "coffee", "tea", "juice", "water"}
        text_lower = text.lower()
        has_food = any(w in text_lower for w in food_words)
        if not has_food:
            raw["nutrition"] = None
        else:
            protein_total = 0.0
            cal_total = 0.0
            for item in nutrition["items"]:
                # Clamp protein
                if item.get("protein_g") is not None:
                    if item["protein_g"] > MAX_PROTEIN_PER_ITEM_G:
                        item["protein_g"] = MAX_PROTEIN_PER_ITEM_G
                        item["confidence"] = "low"
                    protein_total += item["protein_g"]
                # Clamp calories
                if item.get("calories_kcal") is not None:
                    if item["calories_kcal"] > MAX_CALORIES_PER_ITEM:
                        item["calories_kcal"] = MAX_CALORIES_PER_ITEM
                        item["confidence"] = "low"
                    cal_total += item["calories_kcal"]
            # Override model totals with recomputed sums
            raw["nutrition"]["protein_g"] = round(protein_total, 2) if protein_total else None
            raw["nutrition"]["calories_kcal"] = round(cal_total, 2) if cal_total else None
    else:
        raw["nutrition"] = None

    # --- Hydration clamp ---
    if raw.get("hydration_ml") is not None and raw["hydration_ml"] > MAX_HYDRATION_PER_LOG_ML:
        raw["hydration_ml"] = MAX_HYDRATION_PER_LOG_ML

    # --- Workout clamp ---
    workout = raw.get("workout")
    if workout and workout.get("duration_mins") is not None:
        if workout["duration_mins"] > MAX_WORKOUT_DURATION_MINS:
            workout["duration_mins"] = MAX_WORKOUT_DURATION_MINS

    return raw


async def _mark_failed(database, log_id, reason: str):
    from bson import ObjectId
    await asyncio.get_event_loop().run_in_executor(
        None,
        lambda: database["daily_logs"].update_one(
            {"_id": ObjectId(log_id)},
            {"$set": {
                "extraction_status": "failed",
                "extraction_error": reason,
                "updated_at": datetime.now(timezone.utc),
            }},
        )
    )


async def _within_daily_cap(database, user_id: str, date_key: str, cap: int = 120) -> bool:
    day = database["days"].find_one({"user_id": user_id, "date": date_key})
    if day is None:
        return True
    return (day.get("gemini_calls", 0) or 0) < cap


def _increment_gemini_calls(database, user_id: str, date_key: str):
    database["days"].update_one(
        {"user_id": user_id, "date": date_key},
        {"$inc": {"gemini_calls": 1},
         "$setOnInsert": {"created_at": datetime.now(timezone.utc)}},
        upsert=True,
    )


async def extract_log(database, log_id: str):
    """Background task: extract one log entry with Gemini."""
    from bson import ObjectId
    loop = asyncio.get_event_loop()

    def _db_find():
        return database["daily_logs"].find_one({"_id": ObjectId(log_id)})

    log = await loop.run_in_executor(None, _db_find)
    if not log:
        return

    snapshot_hash = log.get("text_hash", "")
    date_key = log["date"]
    user_id = log["user_id"]

    # Daily cap check
    cap_ok = await _within_daily_cap(database, user_id, date_key)
    if not cap_ok:
        await _mark_failed(database, log_id, "daily_cap_reached")
        return

    # Fetch user goal for context
    def _get_user():
        return database["users"].find_one({"user_id": user_id}, {"goal": 1, "_id": 0})

    user = await loop.run_in_executor(None, _get_user)
    goal = (user or {}).get("goal", "general")

    # Get context entries (previous ≤3 from same day)
    def _get_context():
        return list(database["daily_logs"].find(
            {"user_id": user_id, "date": date_key, "extraction_status": "done",
             "timestamp": {"$lt": log["timestamp"]}},
            {"text": 1, "_id": 0}
        ).sort("timestamp", 1).limit(3))

    context_entries = await loop.run_in_executor(None, _get_context)

    local_ts = log["timestamp"].astimezone(IST).strftime("%H:%M IST")
    context_text = ""
    if context_entries:
        context_text = "\n\nContext entries from earlier today (read-only, do NOT extract from these):\n" + \
            "\n".join(f"- {e['text']}" for e in context_entries)

    prompt = (
        f"You extract structured facts from ONE short journal entry for a personal health journal.\n"
        f"User goal: {goal}. Entry time (IST): {local_ts}.\n"
        f"Rules:\n"
        f"- Extract only what is stated or clearly implied. If a quantity is missing, estimate a typical Indian portion and set confidence 'medium' or 'low'.\n"
        f"- If the user gave explicit numbers (e.g. '30g protein'), use them with source 'explicit_user_value'.\n"
        f"- One entry may contain several things: food, water, workout, learning, habits, mood. Fill only what's present; use null otherwise.\n"
        f"- goal_alignment: rate this entry for the goal '{goal}' as good | neutral | poor | not_applicable, with a one-sentence reason and quality_flags.\n"
        f"- Water counts only if a volume or a glass/bottle is mentioned. Assume 1 glass = 250ml, 1 bottle = 1000ml unless stated.\n"
        f"- Return JSON only matching the schema. No commentary.\n"
        f"Entry: \"\"\"{log['text']}\"\"\""
        f"{context_text}"
    )

    delays = [1, 3, 8]
    for attempt in range(1, 4):
        try:
            result, _model = await loop.run_in_executor(
                None, lambda: generate_structured(EntryExtraction, prompt)
            )
            cleaned = _validate_and_recompute(result, log["text"])

            # Optimistic guard: only write if text unchanged
            def _write():
                return database["daily_logs"].update_one(
                    {"_id": ObjectId(log_id), "text_hash": snapshot_hash},
                    {"$set": {
                        "extracted": cleaned,
                        "extraction_status": "done",
                        "extracted_at": datetime.now(timezone.utc),
                        "extraction_error": None,
                        "updated_at": datetime.now(timezone.utc),
                    }},
                )

            updated = await loop.run_in_executor(None, _write)
            if updated.matched_count == 0:
                # Text changed while we were extracting; a new task was already enqueued
                return

            # Increment call counter
            await loop.run_in_executor(
                None, lambda: _increment_gemini_calls(database, user_id, date_key)
            )
            return

        except Exception as e:
            err_str = str(e)[:200]
            await loop.run_in_executor(
                None,
                lambda err=err_str: database["daily_logs"].update_one(
                    {"_id": ObjectId(log_id)},
                    {"$set": {
                        "extraction_attempts": attempt,
                        "extraction_error": err,
                        "updated_at": datetime.now(timezone.utc),
                    }},
                )
            )
            if attempt < 3:
                await asyncio.sleep(delays[attempt - 1])

    await _mark_failed(database, log_id, "gemini_error")


async def sweeper(database):
    """Re-enqueue pending logs that have been stuck for > 2 minutes (e.g. after server restart)."""
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=2)
    stuck = list(database["daily_logs"].find({
        "extraction_status": "pending",
        "updated_at": {"$lt": cutoff},
    }, {"_id": 1}))
    for log in stuck:
        asyncio.create_task(extract_log(database, str(log["_id"])))
