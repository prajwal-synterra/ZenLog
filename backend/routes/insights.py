import os
from datetime import date, datetime, timezone

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException
from pymongo.database import Database

from backend.ai.extraction_service import INSIGHT_PROMPT_VERSION, generate_period_insight
from backend.models.analytics import InsightResponse
from backend.models.log import IST
from backend.routes.dependencies import get_auth_context, get_database
from backend.routes.stats import _period_dates
from backend.services.analytics_service import aggregate_period


router = APIRouter(prefix="/api/insights", tags=["insights"])


def _get_insight(period: str, anchor: date | None, auth_context: dict, database: Database):
    current_day = datetime.now(IST).date()
    anchor = anchor or current_day
    if anchor > current_day:
        raise HTTPException(status_code=422, detail="Insights cannot use a future date.")
    start, end = _period_dates(period, anchor)
    end = min(end, current_day)
    user_id = auth_context["user"]["user_id"]
    reports = database["reports"]
    key = {"user_id": user_id, "period": period, "period_start": start.isoformat()}
    existing = reports.find_one(key)
    if existing:
        period_full_end = _period_dates(period, anchor)[1]
        if start <= current_day <= period_full_end:
            fresh_summary = aggregate_period(database, user_id, period, start, end)
            fresh_summary.pop("tracked_days", None)
            return InsightResponse(
                report_id=str(existing["_id"]),
                period=existing["period"],
                period_start=date.fromisoformat(existing["period_start"]),
                period_end=date.fromisoformat(existing["period_end"]),
                generated_at=existing["generated_at"],
                summary=fresh_summary,
                insight=existing["insight"],
            )
        return InsightResponse(
            report_id=str(existing["_id"]),
            period=existing["period"],
            period_start=date.fromisoformat(existing["period_start"]),
            period_end=date.fromisoformat(existing["period_end"]),
            generated_at=existing["generated_at"],
            summary=existing["summary"],
            insight=existing["insight"],
        )

    summary = aggregate_period(database, user_id, period, start, end)
    summary.pop("tracked_days", None)
    try:
        insight, model_used = generate_period_insight(period, summary)
    except Exception:
        raise HTTPException(
            status_code=503,
            detail="Insight generation failed; existing journal and statistics are unchanged.",
        ) from None

    report = {
        **key,
        "period_end": end.isoformat(),
        "summary": summary,
        "insight": insight.model_dump(mode="json"),
        "prompt_version": INSIGHT_PROMPT_VERSION,
        "model": model_used,
        "generated_at": datetime.now(timezone.utc),
    }
    result = reports.insert_one(report)
    return InsightResponse(
        report_id=str(result.inserted_id),
        period=period,
        period_start=start,
        period_end=end,
        generated_at=report["generated_at"],
        summary=summary,
        insight=insight,
    )


@router.get("/weekly", response_model=InsightResponse)
def weekly_insight(
    date: date | None = None,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return _get_insight("weekly", date, auth_context, database)


@router.get("/monthly", response_model=InsightResponse)
def monthly_insight(
    date: date | None = None,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    return _get_insight("monthly", date, auth_context, database)