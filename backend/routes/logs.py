from datetime import date as date_type
from datetime import datetime, timedelta, timezone
import asyncio
import hashlib

from bson import ObjectId
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse
from pymongo.errors import PyMongoError
from pymongo.database import Database

from backend.ai.entry_extraction import extract_log, _compute_text_hash
from backend.core.timeutil import IST, logical_date, now_ist
from backend.models.log import (
    LogCreateRequest,
    LogResponse,
    LogUpdateRequest,
    StructuredLogCreateRequest,
    RepeatLogRequest,
)
from backend.routes.dependencies import get_auth_context, get_database


router = APIRouter(prefix="/api/logs", tags=["logs"])

DAY_CUTOFF_HOURS = 4


def touch_day(database: Database, user_id: str, day_str: str) -> None:
    """
    Module 2 requirement:
    Called on any log create/update/delete.
    (a) Marks that day's cached AI verdict as stale/modified.
    (b) Invalidates weekly/monthly periodic reports covering day_str.
    """
    now = datetime.now(timezone.utc)
    # 1. Invalidate periodic reports (weekly / monthly)
    database["reports"].delete_many({
        "user_id": user_id,
        "period_start": {"$lte": day_str},
        "period_end": {"$gte": day_str},
    })
    # 2. Mark day record as having data changed since review
    database["days"].update_one(
        {"user_id": user_id, "date": day_str},
        {"$set": {
            "data_changed_since_review": True,
            "updated_at": now,
        }},
    )


def _find_owned_log(database: Database, log_id: str, user_id: str) -> dict:
    if not ObjectId.is_valid(log_id):
        raise HTTPException(status_code=404, detail="Log not found.")
    log = database["daily_logs"].find_one({"_id": ObjectId(log_id), "user_id": user_id})
    if log is None:
        raise HTTPException(status_code=404, detail="Log not found.")
    return log


def serialize_log(document: dict) -> LogResponse:
    ts = document.get("logged_at") or document.get("timestamp") or datetime.now(timezone.utc)
    local_timestamp = ts.astimezone(IST)
    day_str = document.get("logical_date") or document.get("date")

    return LogResponse(
        id=str(document["_id"]),
        user_id=document["user_id"],
        date=date_type.fromisoformat(day_str),
        logical_date=day_str,
        timestamp=local_timestamp,
        logged_at=local_timestamp,
        time_display=local_timestamp.strftime("%I:%M %p IST"),
        text=document["text"],
        source=document.get("source", "text"),
        extraction_status=document.get("extraction_status", "done"),
        extracted=document.get("extracted"),
        overrides=document.get("overrides") or {},
        created_at=document.get("created_at") or datetime.now(timezone.utc),
        client_id=document.get("client_id"),
    )


@router.post("", response_model=LogResponse, status_code=status.HTTP_201_CREATED)
def create_log(
    payload: LogCreateRequest,
    background_tasks: BackgroundTasks,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]

    # C1: Check idempotency with client_id (replay returns existing with 200)
    if payload.client_id:
        existing = database["daily_logs"].find_one({
            "user_id": user_id,
            "client_id": payload.client_id,
        })
        if existing is not None:
            serialized = serialize_log(existing).model_dump(mode="json")
            return JSONResponse(status_code=status.HTTP_200_OK, content=serialized)

    effective_logged_at = payload.logged_at or payload.timestamp or now_ist()
    if effective_logged_at.tzinfo is None:
        effective_logged_at = effective_logged_at.replace(tzinfo=IST)
    effective_logged_at = effective_logged_at.astimezone(IST)

    current_ist = now_ist()
    # Reject logged_at more than 5 minutes in the future
    if effective_logged_at > current_ist + timedelta(minutes=5):
        raise HTTPException(
            status_code=422,
            detail="logged_at cannot be more than 5 minutes in the future.",
        )

    # Derive logical date (4 AM rule in IST)
    if payload.logged_at or payload.timestamp:
        day_key = logical_date(effective_logged_at)
    elif payload.date:
        today_date = current_ist.date()
        if payload.date > today_date:
            raise HTTPException(status_code=422, detail="Cannot log entries for future dates.")
        day_key = payload.date.isoformat()
    else:
        day_key = logical_date(effective_logged_at)

    now = datetime.now(timezone.utc)
    text_hash = _compute_text_hash(payload.text)

    document = {
        "user_id": user_id,
        "client_id": payload.client_id,
        "date": day_key,
        "logical_date": day_key,
        "timestamp": effective_logged_at.astimezone(timezone.utc),
        "logged_at": effective_logged_at.astimezone(timezone.utc),
        "tz": "Asia/Kolkata",
        "source": payload.source or "text",
        "meta": payload.meta or {},
        "text": payload.text,
        "text_hash": text_hash,
        "extraction_status": "pending",
        "extraction_error": None,
        "extraction_attempts": 0,
        "extracted_at": None,
        "extracted": None,
        "overrides": {},
        "created_at": now,
        "updated_at": now,
    }
    result = database["daily_logs"].insert_one(document)
    document["_id"] = result.inserted_id
    log_id = str(result.inserted_id)

    touch_day(database, user_id, day_key)

    # Enqueue per-entry background extraction
    background_tasks.add_task(extract_log, database, log_id)

    return serialize_log(document)


@router.post("/structured", response_model=LogResponse, status_code=status.HTTP_201_CREATED)
def create_structured_log(
    payload: StructuredLogCreateRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Creates a log whose metrics are already known (quick water, saved meals, photos, labels).
    Marks extraction_status: done immediately with NO Gemini API call.
    """
    user_id = auth_context["user"]["user_id"]

    if payload.client_id:
        existing = database["daily_logs"].find_one({
            "user_id": user_id,
            "client_id": payload.client_id,
        })
        if existing is not None:
            serialized = serialize_log(existing).model_dump(mode="json")
            return JSONResponse(status_code=status.HTTP_200_OK, content=serialized)

    effective_logged_at = payload.logged_at or payload.timestamp or now_ist()
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
    text_hash = _compute_text_hash(payload.text)

    document = {
        "user_id": user_id,
        "client_id": payload.client_id,
        "date": day_key,
        "logical_date": day_key,
        "timestamp": effective_logged_at.astimezone(timezone.utc),
        "logged_at": effective_logged_at.astimezone(timezone.utc),
        "tz": "Asia/Kolkata",
        "source": payload.source or "structured",
        "meta": payload.meta or {},
        "text": payload.text,
        "text_hash": text_hash,
        "extraction_status": "done",
        "extraction_error": None,
        "extraction_attempts": 1,
        "extracted_at": now,
        "extracted": payload.extracted,
        "overrides": {},
        "created_at": now,
        "updated_at": now,
    }
    result = database["daily_logs"].insert_one(document)
    document["_id"] = result.inserted_id

    touch_day(database, user_id, day_key)

    return serialize_log(document)


@router.post("/{log_id}/repeat", response_model=LogResponse, status_code=status.HTTP_201_CREATED)
def repeat_log(
    log_id: str,
    payload: RepeatLogRequest | None = None,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Copies an existing entry (text + extracted macros) to now or specified logged_at.
    source: 'repeat'. No Gemini API call needed.
    """
    user_id = auth_context["user"]["user_id"]
    existing = _find_owned_log(database, log_id, user_id)

    if payload and payload.client_id:
        duplicate = database["daily_logs"].find_one({
            "user_id": user_id,
            "client_id": payload.client_id,
        })
        if duplicate is not None:
            serialized = serialize_log(duplicate).model_dump(mode="json")
            return JSONResponse(status_code=status.HTTP_200_OK, content=serialized)

    effective_logged_at = (payload.logged_at if payload else None) or (payload.timestamp if payload else None) or now_ist()
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
    text_hash = _compute_text_hash(existing["text"])

    document = {
        "user_id": user_id,
        "client_id": payload.client_id if payload else None,
        "date": day_key,
        "logical_date": day_key,
        "timestamp": effective_logged_at.astimezone(timezone.utc),
        "logged_at": effective_logged_at.astimezone(timezone.utc),
        "tz": "Asia/Kolkata",
        "source": "repeat",
        "meta": {"original_log_id": str(existing["_id"])},
        "text": existing["text"],
        "text_hash": text_hash,
        "extraction_status": "done",
        "extraction_error": None,
        "extraction_attempts": 1,
        "extracted_at": now,
        "extracted": existing.get("extracted"),
        "overrides": existing.get("overrides") or {},
        "created_at": now,
        "updated_at": now,
    }
    result = database["daily_logs"].insert_one(document)
    document["_id"] = result.inserted_id

    touch_day(database, user_id, day_key)

    return serialize_log(document)


@router.get("/today", response_model=list[LogResponse])
def get_today_logs(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Deprecated alias — kept for backward compat. Use GET /api/days/{date}/view instead."""
    today = logical_date(now_ist())
    documents = database["daily_logs"].find(
        {"user_id": auth_context["user"]["user_id"], "date": today}
    ).sort("timestamp", 1)
    return [serialize_log(document) for document in documents]


@router.get("", response_model=list[LogResponse])
def get_logs(
    start_date: date_type | None = Query(default=None),
    end_date: date_type | None = Query(default=None),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    if (start_date is None) != (end_date is None):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Provide both start_date and end_date, or neither.",
        )
    if start_date is None:
        start_date = end_date = now_ist().date()
    elif start_date > end_date:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="start_date must be on or before end_date.",
        )
    documents = database["daily_logs"].find({
        "user_id": auth_context["user"]["user_id"],
        "date": {"$gte": start_date.isoformat(), "$lte": end_date.isoformat()},
    }).sort([("date", 1), ("timestamp", 1)])
    return [serialize_log(document) for document in documents]


@router.put("/{log_id}", response_model=LogResponse)
def update_log(
    log_id: str,
    payload: LogUpdateRequest,
    background_tasks: BackgroundTasks,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    existing = _find_owned_log(database, log_id, user_id)
    old_day_key = existing.get("logical_date") or existing["date"]
    new_day_key = old_day_key

    update: dict = {"updated_at": datetime.now(timezone.utc)}
    text_changed = False

    if payload.text is not None and payload.text != existing["text"]:
        text_changed = True
        new_hash = _compute_text_hash(payload.text)
        update["text"] = payload.text
        update["text_hash"] = new_hash
        update["extraction_status"] = "pending"
        update["extracted"] = None
        update["extraction_error"] = None
        update["extraction_attempts"] = 0
        update["overrides"] = {}  # Clear overrides when text changes

    effective_dt = payload.logged_at or payload.timestamp
    if effective_dt is not None:
        if effective_dt.tzinfo is None:
            effective_dt = effective_dt.replace(tzinfo=IST)
        effective_dt_ist = effective_dt.astimezone(IST)
        new_day_key = logical_date(effective_dt_ist)
        update["timestamp"] = effective_dt_ist.astimezone(timezone.utc)
        update["logged_at"] = effective_dt_ist.astimezone(timezone.utc)
        update["date"] = new_day_key
        update["logical_date"] = new_day_key
    elif payload.date is not None:
        new_day_key = payload.date.isoformat()
        update["date"] = new_day_key
        update["logical_date"] = new_day_key

    try:
        database["daily_logs"].update_one(
            {"_id": existing["_id"], "user_id": user_id},
            {"$set": update},
        )
    except PyMongoError:
        raise HTTPException(status_code=503, detail="Could not update log.") from None

    touch_day(database, user_id, old_day_key)
    if new_day_key != old_day_key:
        touch_day(database, user_id, new_day_key)

    if text_changed:
        background_tasks.add_task(extract_log, database, log_id)

    saved = database["daily_logs"].find_one({"_id": existing["_id"]})
    return serialize_log(saved)


@router.delete("/{log_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_log(
    log_id: str,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    existing = _find_owned_log(database, log_id, user_id)
    day_key = existing.get("logical_date") or existing["date"]
    database["daily_logs"].delete_one({"_id": existing["_id"], "user_id": user_id})
    touch_day(database, user_id, day_key)


@router.patch("/{log_id}/override")
def override_log(
    log_id: str,
    payload: dict,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Manual correction: {protein_g, calories_kcal, hydration_ml}. Pass null to clear."""
    user_id = auth_context["user"]["user_id"]
    existing = _find_owned_log(database, log_id, user_id)
    day_key = existing.get("logical_date") or existing["date"]

    allowed_keys = {"protein_g", "calories_kcal", "hydration_ml"}
    overrides = existing.get("overrides") or {}

    for key, val in payload.items():
        if key not in allowed_keys:
            raise HTTPException(status_code=422, detail=f"Unknown override key: {key}")
        if val is None:
            overrides.pop(key, None)
        else:
            overrides[key] = val

    database["daily_logs"].update_one(
        {"_id": existing["_id"], "user_id": user_id},
        {"$set": {"overrides": overrides, "updated_at": datetime.now(timezone.utc)}},
    )
    touch_day(database, user_id, day_key)
    return {"detail": "Override saved.", "overrides": overrides}


@router.post("/{log_id}/retry")
def retry_log_extraction(
    log_id: str,
    background_tasks: BackgroundTasks,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Re-run extraction for a failed log."""
    user_id = auth_context["user"]["user_id"]
    existing = _find_owned_log(database, log_id, user_id)
    if existing.get("extraction_status") not in ("failed", "pending"):
        raise HTTPException(status_code=400, detail="Log is not in a retryable state.")

    database["daily_logs"].update_one(
        {"_id": existing["_id"]},
        {"$set": {
            "extraction_status": "pending",
            "extraction_error": None,
            "extraction_attempts": 0,
            "updated_at": datetime.now(timezone.utc),
        }},
    )
    background_tasks.add_task(extract_log, database, log_id)
    return {"detail": "Extraction retry queued.", "extraction_status": "pending"}