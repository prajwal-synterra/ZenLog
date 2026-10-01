from datetime import date, datetime, timedelta, timezone
import os

from fastapi import HTTPException, status
from pymongo.errors import DuplicateKeyError
from pymongo.database import Database

from backend.ai.extraction_service import EXTRACTION_PROMPT_VERSION, extract_day
from backend.models.days import DailyRecordResponse
from backend.models.extraction import DailyExtraction
from backend.models.log import IST


def _serialize_record(record: dict) -> DailyRecordResponse:
    return DailyRecordResponse(
        record_id=str(record["_id"]),
        user_id=record["user_id"],
        date=date.fromisoformat(record["date"]),
        schema_version=record.get("schema_version", "1.0"),
        status=record["status"],
        sleep=record.get("sleep", {}),
        wake=record.get("wake", {}),
        nutrition=record.get("nutrition", {}),
        fitness=record.get("fitness", {}),
        learning=record.get("learning", {}),
        habits=record.get("habits", {}),
        mood=record.get("mood", {}),
        insights=record.get("insights", {}),
        processing=record.get("processing", {}),
    )


def _build_record(
    extraction: DailyExtraction,
    model_used: str | None,
    user: dict,
    user_id: str,
    day: date,
    sleep_time: str,
    created_at: datetime,
    wake: dict | None = None,
) -> dict:
    meals = []
    protein_total = 0.0
    calories_total = 0.0
    has_protein = False
    has_calories = False

    for meal in extraction.nutrition.meals:
        meal_data = meal.model_dump(mode="json")
        meal_protein = sum(
            item.protein_g for item in meal.items if item.protein_g is not None
        )
        if any(item.protein_g is not None for item in meal.items):
            has_protein = True
            protein_total += meal_protein
        if any(item.calories_kcal is not None for item in meal.items):
            has_calories = True
            calories_total += sum(
                item.calories_kcal
                for item in meal.items
                if item.calories_kcal is not None
            )
        meal_data["meal_protein_g"] = round(meal_protein, 2) if meal_protein else None
        meals.append(meal_data)

    daily_target = user.get("daily_protein_target_g")
    protein_value = round(protein_total, 2) if has_protein else None
    nutrition = {
        "meals": meals,
        "daily_totals": {
            "protein_g": protein_value,
            "calories_kcal": round(calories_total, 2) if has_calories else None,
            "hydration_ml": sum(extraction.nutrition.water_intake_ml)
            if extraction.nutrition.water_intake_ml
            else None,
            "protein_target_g": daily_target,
            "target_percentage": round(protein_total / daily_target * 100, 1)
            if has_protein and daily_target
            else None,
            "remaining_protein_g": round(max(daily_target - protein_total, 0), 2)
            if has_protein and daily_target
            else None,
        },
    }
    extracted = extraction.model_dump(mode="json")
    return {
        "user_id": user_id,
        "date": day.isoformat(),
        "schema_version": "1.0",
        "status": "COMPLETED",
        "sleep": {"sleep_time": sleep_time, "source": "user"},
        "wake": wake or {},
        "nutrition": nutrition,
        "fitness": {"workouts": extracted["workouts"]},
        "learning": {"activities": extracted["learning"]},
        "habits": {"observations": extracted["habits"]},
        "mood": {"observations": extracted["moods"]},
        "insights": extracted["insights"],
        "processing": {
            "processed_at": datetime.now(timezone.utc),
            "model": model_used,
            "prompt_version": EXTRACTION_PROMPT_VERSION,
        },
        "created_at": created_at,
        "updated_at": datetime.now(timezone.utc),
    }


def process_day(
    database: Database,
    user: dict,
    day: date,
    sleep_time: str,
    force: bool = False,
) -> DailyRecordResponse:
    user_id = user["user_id"]
    day_key = day.isoformat()
    records = database["daily_records"]
    existing = records.find_one({"user_id": user_id, "date": day_key})

    if existing:
        if existing["status"] == "PROCESSING":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This day is already being processed.",
            )
        if existing["status"] == "COMPLETED" and not force:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This day is already completed.",
            )

    now = datetime.now(timezone.utc)
    wake_to_preserve = existing.get("wake", {}) if existing else {}

    if existing:
        record_id = existing["_id"]
        claim = records.update_one(
            {"_id": record_id},
            {
                "$set": {
                    "status": "PROCESSING",
                    "sleep": {"sleep_time": sleep_time, "source": "user"},
                    "updated_at": now,
                },
                "$unset": {
                    "nutrition": "",
                    "fitness": "",
                    "learning": "",
                    "habits": "",
                    "mood": "",
                    "insights": "",
                },
            },
        )
    else:
        try:
            result = records.insert_one(
                {
                    "user_id": user_id,
                    "date": day_key,
                    "schema_version": "1.0",
                    "status": "PROCESSING",
                    "sleep": {"sleep_time": sleep_time, "source": "user"},
                    "wake": {},
                    "created_at": now,
                    "updated_at": now,
                }
            )
            record_id = result.inserted_id
        except DuplicateKeyError:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This day is already being processed.",
            ) from None

    try:
        logs = list(
            database["daily_logs"].find(
                {"user_id": user_id, "date": day_key},
                {"_id": 0, "timestamp": 1, "text": 1},
            ).sort("timestamp", 1)
        )
        if logs:
            extraction, model_used = extract_day(logs)
        else:
            extraction = DailyExtraction()
            model_used = None

        final_record = _build_record(
            extraction,
            model_used,
            user,
            user_id,
            day,
            sleep_time,
            now,
            wake=wake_to_preserve,
        )
        records.update_one({"_id": record_id}, {"$set": final_record})
        database["reports"].delete_many(
            {
                "user_id": user_id,
                "period_start": {"$lte": day_key},
                "period_end": {"$gte": day_key},
            }
        )
        saved = records.find_one({"_id": record_id})
        return _serialize_record(saved)
    except Exception as error:
        records.update_one(
            {"_id": record_id},
            {
                "$set": {
                    "status": "PROCESSING_FAILED",
                    "processing": {
                        "error_type": type(error).__name__,
                        "failed_at": datetime.now(timezone.utc),
                    },
                    "updated_at": datetime.now(timezone.utc),
                }
            },
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Day processing failed. Raw logs are preserved; submit again to retry.",
        ) from None


def record_wake(
    database: Database,
    user: dict,
    day: date,
    wake_time: str,
) -> dict:
    user_id = user["user_id"]
    day_key = day.isoformat()
    records = database["daily_records"]
    now = datetime.now(timezone.utc)
    wake_data = {
        "wake_time": wake_time,
        "source": "user",
        "recorded_at": now,
    }
    records.update_one(
        {"user_id": user_id, "date": day_key},
        {
            "$set": {
                "wake": wake_data,
                "updated_at": now,
            },
            "$setOnInsert": {
                "schema_version": "1.0",
                "status": "OPEN",
                "sleep": {},
                "nutrition": {},
                "fitness": {},
                "learning": {},
                "habits": {},
                "mood": {},
                "insights": {},
                "processing": {},
                "created_at": now,
            },
        },
        upsert=True,
    )
    return wake_data


def edit_day_sleep(
    database: Database,
    user: dict,
    day: date,
    sleep_time: str,
    reprocess: bool = False,
) -> DailyRecordResponse:
    user_id = user["user_id"]
    day_key = day.isoformat()
    records = database["daily_records"]
    existing = records.find_one({"user_id": user_id, "date": day_key})

    if not existing:
        return process_day(database, user, day, sleep_time)

    if reprocess or existing.get("status") in {"PROCESSING_FAILED", "OPEN"}:
        return process_day(database, user, day, sleep_time, force=True)

    now = datetime.now(timezone.utc)
    records.update_one(
        {"_id": existing["_id"]},
        {
            "$set": {
                "sleep": {"sleep_time": sleep_time, "source": "user"},
                "updated_at": now,
            }
        },
    )
    saved = records.find_one({"_id": existing["_id"]})
    return _serialize_record(saved)


def get_day_prompt_status(database: Database, user_id: str) -> dict:
    today = datetime.now(IST).date()
    yesterday = today - timedelta(days=1)

    today_key = today.isoformat()
    yesterday_key = yesterday.isoformat()

    today_record = database["daily_records"].find_one({"user_id": user_id, "date": today_key})
    yesterday_record = database["daily_records"].find_one({"user_id": user_id, "date": yesterday_key})

    yesterday_logs_count = database["daily_logs"].count_documents(
        {"user_id": user_id, "date": yesterday_key}
    )

    # Needs yesterday sleep if yesterday had logs (or open record) and sleep was never completed
    needs_yesterday_sleep = bool(
        yesterday_logs_count > 0 and (not yesterday_record or yesterday_record.get("status") != "COMPLETED")
    )

    # Needs today wake if today wake_time is not set
    today_wake = today_record.get("wake", {}).get("wake_time") if today_record else None
    needs_today_wake = bool(today_wake is None)

    return {
        "today": today,
        "yesterday": yesterday,
        "needs_yesterday_sleep": needs_yesterday_sleep,
        "needs_today_wake": needs_today_wake,
        "yesterday_status": yesterday_record["status"] if yesterday_record else ("OPEN" if yesterday_logs_count > 0 else "NO_LOGS"),
        "today_status": today_record["status"] if today_record else "OPEN",
        "yesterday_sleep_time": yesterday_record.get("sleep", {}).get("sleep_time") if yesterday_record else None,
        "today_wake_time": today_wake,
    }


def get_record(database: Database, user_id: str, day: date) -> dict | None:
    return database["daily_records"].find_one(
        {"user_id": user_id, "date": day.isoformat()}
    )