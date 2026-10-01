from datetime import date as date_type
from datetime import datetime, timedelta, timezone
import asyncio
import hashlib

from bson import ObjectId
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from pymongo.errors import PyMongoError
from pymongo.database import Database

from backend.ai.entry_extraction import extract_log, _compute_text_hash
from backend.models.log import IST, LogCreateRequest, LogResponse, LogUpdateRequest
from backend.routes.dependencies import get_auth_context, get_database


router = APIRouter(prefix="/api/logs", tags=["logs"])

DAY_CUTOFF_HOURS = 4


def _logical_date(ts: datetime) -> date_type:
    """4 AM boundary rule: logs before 4 AM belong to the previous day."""
    local = ts.astimezone(IST)
    if local.hour < DAY_CUTOFF_HOURS:
        return (local - timedelta(hours=DAY_CUTOFF_HOURS)).date()
    return local.date()


def _find_owned_log(database: Database, log_id: str, user_id: str) -> dict:
    if not ObjectId.is_valid(log_id):
        raise HTTPException(status_code=404, detail="Log not found.")
    log = database["daily_logs"].find_one({"_id": ObjectId(log_id), "user_id": user_id})
    if log is None:
        raise HTTPException(status_code=404, detail="Log not found.")
    return log


def _invalidate_reports(database: Database, user_id: str, day: str) -> None:
    database["reports"].delete_many({
        "user_id": user_id,
        "period_start": {"$lte": day},
        "period_end": {"$gte": day},
    })


def serialize_log(document: dict) -> LogResponse:
    local_timestamp = document["timestamp"].astimezone(IST)
    return LogResponse(
        id=str(document["_id"]),
        user_id=document["user_id"],
        date=date_type.fromisoformat(document["date"]),
        timestamp=local_timestamp,
        time_display=local_timestamp.strftime("%I:%M %p IST"),
        text=document["text"],
        created_at=document["created_at"],
    )


@router.post("", response_model=LogResponse, status_code=status.HTTP_201_CREATED)
def create_log(
    payload: LogCreateRequest,
    background_tasks: BackgroundTasks,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    local_timestamp = payload.timestamp or datetime.now(IST)

    # Reject future-dated logs (explicit date in future)
    if payload.date:
        today = datetime.now(IST).date()
        if payload.date > today:
            raise HTTPException(status_code=422, detail="Cannot log entries for future dates.")
        day_key = payload.date.isoformat()
    else:
        # Apply 4 AM boundary rule
        logical = _logical_date(local_timestamp)
        day_key = logical.isoformat()

    now = datetime.now(timezone.utc)
    text_hash = _compute_text_hash(payload.text)

    document = {
        "user_id": user_id,
        "date": day_key,
        "timestamp": local_timestamp.astimezone(timezone.utc),
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

    _invalidate_reports(database, user_id, day_key)

    # Enqueue per-entry background extraction
    background_tasks.add_task(extract_log, database, log_id)

    return serialize_log(document)


@router.get("/today", response_model=list[LogResponse])
def get_today_logs(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Deprecated alias — kept for backward compat. Use GET /api/days/{date}/view instead."""
    now_ist = datetime.now(IST)
    if now_ist.hour < DAY_CUTOFF_HOURS:
        today = (now_ist - timedelta(hours=DAY_CUTOFF_HOURS)).date().isoformat()
    else:
        today = now_ist.date().isoformat()
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
        start_date = end_date = datetime.now(IST).date()
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
    day_key = existing["date"]

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

    if payload.timestamp is not None:
        timestamp_ist = payload.timestamp.astimezone(IST)
        new_date = _logical_date(timestamp_ist)
        update["timestamp"] = timestamp_ist.astimezone(timezone.utc)
        update["date"] = new_date.isoformat()
        day_key = new_date.isoformat()
    elif payload.date is not None:
        update["date"] = payload.date.isoformat()
        day_key = payload.date.isoformat()

    try:
        database["daily_logs"].update_one(
            {"_id": existing["_id"], "user_id": user_id},
            {"$set": update},
        )
    except PyMongoError:
        raise HTTPException(status_code=503, detail="Could not update log.") from None

    _invalidate_reports(database, user_id, day_key)
    _invalidate_reports(database, user_id, existing["date"])

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
    database["daily_logs"].delete_one({"_id": existing["_id"], "user_id": user_id})
    _invalidate_reports(database, user_id, existing["date"])


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
    _invalidate_reports(database, user_id, existing["date"])
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