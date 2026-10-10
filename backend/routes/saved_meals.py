import re
from datetime import datetime, timedelta, timezone
from typing import Any

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse
from pymongo.database import Database

from backend.ai.entry_extraction import _compute_text_hash
from backend.core.timeutil import IST, logical_date, now_ist
from backend.models.log import LogResponse
from backend.models.saved_meals import (
    SavedMealCreateRequest,
    SavedMealLogRequest,
    SavedMealResponse,
    SavedMealSuggestion,
    SavedMealUpdateRequest,
)
from backend.routes.dependencies import get_auth_context, get_database
from backend.routes.logs import serialize_log, touch_day

router = APIRouter(prefix="/api/saved-meals", tags=["saved-meals"])


def _serialize_saved_meal(doc: dict[str, Any]) -> SavedMealResponse:
    return SavedMealResponse(
        id=str(doc["_id"]),
        user_id=doc["user_id"],
        name=doc.get("name", "Saved Meal"),
        raw_text=doc.get("raw_text", ""),
        extracted=doc.get("extracted") or {},
        use_count=doc.get("use_count", 0),
        last_used_at=doc.get("last_used_at"),
        pinned=doc.get("pinned", False),
        created_from_log_id=doc.get("created_from_log_id"),
        created_at=doc.get("created_at", datetime.now(timezone.utc)),
        updated_at=doc.get("updated_at", datetime.now(timezone.utc)),
    )


def _scale_extracted(extracted: dict[str, Any], portion: float) -> dict[str, Any]:
    scaled: dict[str, Any] = {}
    for k, v in extracted.items():
        if isinstance(v, (int, float)):
            if k in ("calories", "calories_kcal", "water_ml", "hydration_ml"):
                scaled[k] = round(v * portion)
            else:
                scaled[k] = round(v * portion, 1)
        elif isinstance(v, dict):
            scaled[k] = _scale_extracted(v, portion)
        elif isinstance(v, list):
            scaled_list = []
            for item in v:
                if isinstance(item, dict):
                    scaled_list.append(_scale_extracted(item, portion))
                else:
                    scaled_list.append(item)
            scaled[k] = scaled_list
        else:
            scaled[k] = v
    return scaled


def _normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


@router.get("", response_model=list[SavedMealResponse])
def list_saved_meals(
    sort: str = Query(default="frequent", pattern="^(frequent|recent)$"),
    limit: int = Query(default=20, ge=1, le=100),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    query = {"user_id": user_id}

    if sort == "frequent":
        sort_spec = [("pinned", -1), ("use_count", -1), ("created_at", -1)]
    else:
        sort_spec = [("pinned", -1), ("last_used_at", -1), ("created_at", -1)]

    cursor = database["saved_meals"].find(query).sort(sort_spec).limit(limit)
    return [_serialize_saved_meal(doc) for doc in cursor]


@router.post("", response_model=SavedMealResponse, status_code=status.HTTP_201_CREATED)
def create_saved_meal(
    payload: SavedMealCreateRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    now = datetime.now(timezone.utc)

    if payload.log_id:
        if not ObjectId.is_valid(payload.log_id):
            raise HTTPException(status_code=404, detail="Log entry not found.")
        log = database["daily_logs"].find_one({"_id": ObjectId(payload.log_id), "user_id": user_id})
        if not log:
            raise HTTPException(status_code=404, detail="Log entry not found.")

        extracted = log.get("extracted") or {}
        if not extracted or not any(isinstance(v, (int, float)) and v > 0 for v in extracted.values()):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot save meal: no valid nutritional macros extracted.",
            )

        name = (payload.name or log.get("text", "Saved Meal")).strip()
        raw_text = log.get("text", "").strip()
        created_from_log_id = str(log["_id"])
    else:
        if not payload.extracted or not any(isinstance(v, (int, float)) and v > 0 for v in payload.extracted.values()):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Nutrition values (protein, calories, etc.) are required to save a meal.",
            )
        name = (payload.name or payload.raw_text or "Saved Meal").strip()
        raw_text = (payload.raw_text or payload.name or "").strip()
        extracted = payload.extracted
        created_from_log_id = None

    doc = {
        "user_id": user_id,
        "name": name,
        "raw_text": raw_text,
        "extracted": extracted,
        "use_count": 0,
        "last_used_at": None,
        "pinned": payload.pinned,
        "created_from_log_id": created_from_log_id,
        "created_at": now,
        "updated_at": now,
    }
    result = database["saved_meals"].insert_one(doc)
    doc["_id"] = result.inserted_id
    return _serialize_saved_meal(doc)


@router.put("/{meal_id}", response_model=SavedMealResponse)
def update_saved_meal(
    meal_id: str,
    payload: SavedMealUpdateRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    if not ObjectId.is_valid(meal_id):
        raise HTTPException(status_code=404, detail="Saved meal not found.")

    user_id = auth_context["user"]["user_id"]
    now = datetime.now(timezone.utc)
    updates: dict[str, Any] = {"updated_at": now}

    if payload.name is not None:
        updates["name"] = payload.name.strip()
    if payload.raw_text is not None:
        updates["raw_text"] = payload.raw_text.strip()
    if payload.extracted is not None:
        updates["extracted"] = payload.extracted
    if payload.pinned is not None:
        updates["pinned"] = payload.pinned

    doc = database["saved_meals"].find_one_and_update(
        {"_id": ObjectId(meal_id), "user_id": user_id},
        {"$set": updates},
        return_document=True,
    )
    if not doc:
        raise HTTPException(status_code=404, detail="Saved meal not found.")

    return _serialize_saved_meal(doc)


@router.delete("/{meal_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_saved_meal(
    meal_id: str,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    if not ObjectId.is_valid(meal_id):
        raise HTTPException(status_code=404, detail="Saved meal not found.")

    user_id = auth_context["user"]["user_id"]
    res = database["saved_meals"].delete_one({"_id": ObjectId(meal_id), "user_id": user_id})
    if res.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Saved meal not found.")
    return None


@router.post("/{meal_id}/log", response_model=LogResponse, status_code=status.HTTP_201_CREATED)
def log_saved_meal(
    meal_id: str,
    payload: SavedMealLogRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    if not ObjectId.is_valid(meal_id):
        raise HTTPException(status_code=404, detail="Saved meal not found.")

    user_id = auth_context["user"]["user_id"]
    meal = database["saved_meals"].find_one({"_id": ObjectId(meal_id), "user_id": user_id})
    if not meal:
        raise HTTPException(status_code=404, detail="Saved meal not found.")

    # Idempotency check if client_id was passed
    if payload.client_id:
        duplicate = database["daily_logs"].find_one({
            "user_id": user_id,
            "client_id": payload.client_id,
        })
        if duplicate:
            serialized = serialize_log(duplicate).model_dump(mode="json")
            return JSONResponse(status_code=status.HTTP_200_OK, content=serialized)

    effective_logged_at = payload.logged_at or now_ist()
    if effective_logged_at.tzinfo is None:
        effective_logged_at = effective_logged_at.replace(tzinfo=IST)
    effective_logged_at = effective_logged_at.astimezone(IST)

    current_ist = now_ist()
    if effective_logged_at > current_ist + timedelta(minutes=5):
        raise HTTPException(
            status_code=422,
            detail="logged_at cannot be more than 5 minutes in the future.",
        )

    day_key = logical_date(effective_logged_at)
    now = datetime.now(timezone.utc)

    # Scale macros deterministically by portion
    portion = round(payload.portion, 2)
    extracted_scaled = _scale_extracted(meal.get("extracted") or {}, portion)

    display_text = (
        meal["name"]
        if portion == 1.0
        else f"{meal['name']} ({portion:g}x)"
    )

    log_doc = {
        "user_id": user_id,
        "client_id": payload.client_id,
        "date": day_key,
        "logical_date": day_key,
        "timestamp": effective_logged_at.astimezone(timezone.utc),
        "logged_at": effective_logged_at.astimezone(timezone.utc),
        "tz": "Asia/Kolkata",
        "source": "saved_meal",
        "meta": {
            "saved_meal_id": str(meal["_id"]),
            "portion": portion,
            "original_name": meal["name"],
        },
        "text": display_text,
        "text_hash": _compute_text_hash(display_text),
        "extraction_status": "done",
        "extraction_error": None,
        "extraction_attempts": 1,
        "extracted_at": now,
        "extracted": extracted_scaled,
        "overrides": {},
        "created_at": now,
        "updated_at": now,
    }

    result = database["daily_logs"].insert_one(log_doc)
    log_doc["_id"] = result.inserted_id

    # Increment use count and record last used
    database["saved_meals"].update_one(
        {"_id": meal["_id"]},
        {"$inc": {"use_count": 1}, "$set": {"last_used_at": now}},
    )

    touch_day(database, user_id, day_key)

    return serialize_log(log_doc)


@router.get("/suggestions", response_model=list[SavedMealSuggestion])
def get_saved_meal_suggestions(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Finds normalized text logged 3+ times in the last 30 days that is not yet saved.
    """
    user_id = auth_context["user"]["user_id"]
    cutoff_date = (now_ist() - timedelta(days=30)).date().isoformat()

    # Get already saved normalized texts and names
    existing_saved = database["saved_meals"].find({"user_id": user_id}, {"name": 1, "raw_text": 1})
    saved_keys = set()
    for s in existing_saved:
        if s.get("name"):
            saved_keys.add(_normalize_text(s["name"]))
        if s.get("raw_text"):
            saved_keys.add(_normalize_text(s["raw_text"]))

    # Query completed logs in the last 30 days
    recent_logs = database["daily_logs"].find({
        "user_id": user_id,
        "logical_date": {"$gte": cutoff_date},
        "extraction_status": "done",
        "source": {"$nin": ["water_quick"]},  # Exclude quick water
    }).sort("created_at", -1)

    counts: dict[str, int] = {}
    samples: dict[str, dict[str, Any]] = {}

    for log in recent_logs:
        text = log.get("text", "").strip()
        if not text:
            continue
        norm = _normalize_text(text)
        if norm in saved_keys:
            continue

        extracted = log.get("extracted") or {}
        # Ensure has meaningful macro values
        has_macros = any(isinstance(v, (int, float)) and v > 0 for v in extracted.values())
        if not has_macros:
            continue

        counts[norm] = counts.get(norm, 0) + 1
        if norm not in samples:
            samples[norm] = {
                "name": text,
                "raw_text": text,
                "sample_log_id": str(log["_id"]),
                "sample_extracted": extracted,
            }

    suggestions = []
    for norm, count in counts.items():
        if count >= 3:
            s = samples[norm]
            suggestions.append(SavedMealSuggestion(
                name=s["name"],
                raw_text=s["raw_text"],
                count=count,
                sample_log_id=s["sample_log_id"],
                sample_extracted=s["sample_extracted"],
            ))

    suggestions.sort(key=lambda x: x.count, reverse=True)
    return suggestions
