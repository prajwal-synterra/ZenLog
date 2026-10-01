from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

from backend.models.days import (
    DailyHistoryResponse,
    DailyRecordResponse,
    DayPromptStatusResponse,
    EditSleepRequest,
    ReprocessDayRequest,
    SleepRequest,
    WakeRequest,
)
from backend.models.log import IST
from backend.routes.dependencies import get_auth_context, get_database
from backend.routes.logs import serialize_log
from backend.services.day_service import (
    _serialize_record,
    edit_day_sleep,
    get_day_prompt_status,
    get_record,
    process_day,
    record_wake,
)


router = APIRouter(prefix="/api/days", tags=["days"])


def _submit(day, payload, auth_context, database):
    today = datetime.now(IST).date()
    if day < today - timedelta(days=1) or day > today:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only today or yesterday can be submitted.",
        )
    return process_day(database, auth_context["user"], day, payload.sleep_time)


@router.get("/prompt-status", response_model=DayPromptStatusResponse)
def prompt_status(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return get_day_prompt_status(database, auth_context["user"]["user_id"])


@router.post("/wake")
def wake_today(
    payload: WakeRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    today = datetime.now(IST).date()
    return record_wake(database, auth_context["user"], today, payload.wake_time)


@router.post("/sleep", response_model=DailyRecordResponse)
def submit_today(
    payload: SleepRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return _submit(datetime.now(IST).date(), payload, auth_context, database)


@router.post("/{day}/wake")
def wake_day(
    day: date,
    payload: WakeRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return record_wake(database, auth_context["user"], day, payload.wake_time)


@router.post("/{day}/sleep", response_model=DailyRecordResponse)
def submit_day(
    day: date,
    payload: SleepRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return _submit(day, payload, auth_context, database)


@router.put("/{day}/sleep", response_model=DailyRecordResponse)
def edit_sleep(
    day: date,
    payload: EditSleepRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return edit_day_sleep(
        database,
        auth_context["user"],
        day,
        payload.sleep_time,
        reprocess=payload.reprocess,
    )


@router.post("/{day}/reprocess", response_model=DailyRecordResponse)
def reprocess_day_route(
    day: date,
    payload: ReprocessDayRequest = ReprocessDayRequest(),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    record = get_record(database, auth_context["user"]["user_id"], day)
    sleep_time = payload.sleep_time or (
        record.get("sleep", {}).get("sleep_time") if record else "23:00"
    )
    return process_day(database, auth_context["user"], day, sleep_time, force=True)


@router.get("/{day}", response_model=DailyHistoryResponse)
def get_day(
    day: date,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    logs = database["daily_logs"].find(
        {"user_id": user_id, "date": day.isoformat()}
    ).sort("timestamp", 1)
    record = get_record(database, user_id, day)
    return DailyHistoryResponse(
        date=day,
        status=record["status"] if record else "OPEN",
        logs=[serialize_log(log) for log in logs],
        record=_serialize_record(record) if record else None,
    )