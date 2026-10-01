from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pymongo.database import Database

from backend.models.analytics import DailyStatsResponse, PeriodStatsResponse
from backend.models.log import IST
from backend.routes.dependencies import get_auth_context, get_database
from backend.services.analytics_service import aggregate_period


router = APIRouter(prefix="/api/stats", tags=["statistics"])


@router.get("/daily/{day}", response_model=DailyStatsResponse)
def daily_stats(
    day: date,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    record = database["daily_records"].find_one(
        {"user_id": user_id, "date": day.isoformat()}
    )
    log_count = database["daily_logs"].count_documents(
        {"user_id": user_id, "date": day.isoformat()}
    )
    totals = record.get("nutrition", {}).get("daily_totals", {}) if record else {}
    protein = totals.get("protein_g")
    target = totals.get("protein_target_g")
    workouts = record.get("fitness", {}).get("workouts", []) if record else []
    return DailyStatsResponse(
        date=day,
        status=record["status"].lower() if record else "open",
        log_count=log_count,
        protein_g=protein,
        protein_target_g=target,
        target_percentage=totals.get("target_percentage"),
        remaining_protein_g=totals.get("remaining_protein_g"),
        hydration_ml=totals.get("hydration_ml"),
        workout=bool(workouts),
    )


def _period_dates(period: str, anchor: date) -> tuple[date, date]:
    if period == "weekly":
        start = anchor - timedelta(days=anchor.weekday())
        return start, start + timedelta(days=6)
    start = anchor.replace(day=1)
    next_month = (start.replace(day=28) + timedelta(days=4)).replace(day=1)
    return start, next_month - timedelta(days=1)


def period_stats(
    period: str,
    anchor: date | None,
    auth_context: dict,
    database: Database,
) -> PeriodStatsResponse:
    current_day = datetime.now(IST).date()
    anchor = anchor or current_day
    if anchor > current_day:
        raise HTTPException(status_code=422, detail="Statistics cannot use a future date.")
    start_date, end_date = _period_dates(period, anchor)
    result = aggregate_period(
        database,
        auth_context["user"]["user_id"],
        period,
        start_date,
        min(end_date, current_day),
    )
    return PeriodStatsResponse(**result)


@router.get("/weekly", response_model=PeriodStatsResponse)
def weekly_stats(
    date: date | None = None,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return period_stats("weekly", date, auth_context, database)


@router.get("/monthly", response_model=PeriodStatsResponse)
def monthly_stats(
    date: date | None = None,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return period_stats("monthly", date, auth_context, database)