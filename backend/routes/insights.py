from datetime import date, datetime, timezone
from typing import Any

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pymongo.database import Database

from backend.ai.extraction_service import INSIGHT_PROMPT_VERSION, generate_period_insight
from backend.core.insight_hash import input_hash
from backend.models.analytics import (
    CachedInsightResponse,
    GenerateInsightRequest,
    InsightResponse,
)
from backend.models.log import IST
from backend.routes.dependencies import get_auth_context, get_database
from backend.routes.stats import _period_dates
from backend.services.analytics_service import aggregate_period
from backend.services.close_service import get_user_targets_snapshot
from backend.services.progress_engine import compute_day_totals

router = APIRouter(prefix="/api/insights", tags=["insights"])


def _normalize_period(period: str) -> str:
    p = period.lower().strip()
    if p in ("week", "weekly"):
        return "weekly"
    if p in ("month", "monthly"):
        return "monthly"
    return p


def _get_period_days_and_hash(
    database: Database,
    user_id: str,
    period: str,
    start_date: date,
    end_date: date,
) -> tuple[dict[str, Any], list[dict[str, Any]], str, dict[str, Any]]:
    start_iso = start_date.isoformat()
    end_iso = end_date.isoformat()

    user = database["users"].find_one({"user_id": user_id}, {"_id": 0, "phone_number": 0}) or {}
    targets = get_user_targets_snapshot(user)
    goal = user.get("goal", "muscle_gain")

    entries = list(database["daily_logs"].find({
        "user_id": user_id,
        "date": {"$gte": start_iso, "$lte": end_iso},
    }).sort("timestamp", 1))

    days_map: dict[str, list[dict]] = {}
    for entry in entries:
        d = entry.get("date")
        if d:
            days_map.setdefault(d, []).append(entry)

    records = list(database["daily_records"].find({
        "user_id": user_id,
        "date": {"$gte": start_iso, "$lte": end_iso},
    }))
    sleep_map: dict[str, int] = {}
    for r in records:
        w_time = r.get("wake", {}).get("wake_time")
        s_time = r.get("sleep", {}).get("sleep_time")
        if w_time and s_time:
            try:
                wh, wm = map(int, w_time.split(":"))
                sh, sm = map(int, s_time.split(":"))
                w_tot = wh * 60 + wm
                s_tot = sh * 60 + sm
                dur = (w_tot - s_tot) if w_tot >= s_tot else (w_tot + 1440 - s_tot)
                sleep_map[r["date"]] = dur
            except Exception:
                pass

    days_for_hash: list[dict[str, Any]] = []
    for d_key, d_entries in sorted(days_map.items()):
        t = compute_day_totals(d_entries)
        days_for_hash.append({
            "logical_date": d_key,
            "protein_g": t.get("protein_g", 0.0),
            "calories": t.get("calories_kcal", 0.0),
            "water_ml": t.get("hydration_ml", 0.0),
            "workout": t.get("workout_done", False),
            "sleep_min": sleep_map.get(d_key, 0),
        })

    summary = aggregate_period(database, user_id, period, start_date, end_date)
    summary.pop("tracked_days", None)

    computed_hash = input_hash(days_for_hash, targets, goal, INSIGHT_PROMPT_VERSION)
    return summary, days_for_hash, computed_hash, targets


@router.get("/{period}", response_model=CachedInsightResponse)
def get_cached_insight(
    period: str,
    date: date | None = Query(default=None),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Module 5: Returns cached insight report with status: fresh | stale | none.
    NEVER calls Gemini.
    """
    normalized_period = _normalize_period(period)
    current_day = datetime.now(IST).date()
    anchor = date or current_day
    if anchor > current_day:
        raise HTTPException(status_code=422, detail="Insights cannot use a future date.")

    start, end = _period_dates(normalized_period, anchor)
    end = min(end, current_day)
    user_id = auth_context["user"]["user_id"]

    summary, days_for_hash, current_hash, _ = _get_period_days_and_hash(
        database, user_id, normalized_period, start, end
    )
    days_logged = len(days_for_hash)

    kind = "week" if normalized_period == "weekly" else "month"
    cache_query = {
        "user_id": user_id,
        "kind": kind,
        "range_start": start.isoformat(),
        "range_end": end.isoformat(),
    }
    cached = database["insight_cache"].find_one(cache_query)

    # Fallback to existing reports collection if not yet migrated to insight_cache
    if not cached:
        rep = database["reports"].find_one({
            "user_id": user_id,
            "period": normalized_period,
            "period_start": start.isoformat(),
        })
        if rep and rep.get("insight"):
            cached = {
                "report": rep.get("insight"),
                "input_hash": rep.get("input_hash"),
                "generated_at": rep.get("generated_at"),
            }

    if not cached or not (cached.get("report") or cached.get("insight")):
        return CachedInsightResponse(
            status="none",
            period=normalized_period,
            range_start=start.isoformat(),
            range_end=end.isoformat(),
            report=None,
            insight=None,
            summary=summary,
            generated_at=None,
            input_hash=None,
            current_hash=current_hash,
            days_logged=days_logged,
            can_generate=(days_logged >= 3),
        )

    cached_hash = cached.get("input_hash")
    is_fresh = bool(cached_hash and cached_hash == current_hash)
    status_label = "fresh" if is_fresh else "stale"
    rep_obj = cached.get("report") or cached.get("insight")

    return CachedInsightResponse(
        status=status_label,
        period=normalized_period,
        range_start=start.isoformat(),
        range_end=end.isoformat(),
        report=rep_obj,
        insight=rep_obj,
        summary=summary,
        generated_at=cached.get("generated_at"),
        input_hash=cached_hash,
        current_hash=current_hash,
        days_logged=days_logged,
        can_generate=True,
    )


@router.post("/{period}/generate", response_model=CachedInsightResponse)
def generate_insight(
    period: str,
    payload: GenerateInsightRequest = GenerateInsightRequest(),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Module 5: Generates / updates the AI insight report.
    - Requires at least 3 logged days.
    - If input_hash matches the cache and force is False, returns cached without calling Gemini.
    - Enforces a 10-minute cooldown on regeneration unless force is True.
    - If Gemini fails, falls back to the existing stale report if available.
    """
    normalized_period = _normalize_period(period)
    current_day = datetime.now(IST).date()
    anchor = payload.anchor or current_day
    if anchor > current_day:
        raise HTTPException(status_code=422, detail="Insights cannot use a future date.")

    start, end = _period_dates(normalized_period, anchor)
    end = min(end, current_day)
    user_id = auth_context["user"]["user_id"]

    summary, days_for_hash, current_hash, _ = _get_period_days_and_hash(
        database, user_id, normalized_period, start, end
    )
    days_logged = len(days_for_hash)

    if days_logged < 3:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least 3 tracked days required to generate insights.",
        )

    kind = "week" if normalized_period == "weekly" else "month"
    cache_query = {
        "user_id": user_id,
        "kind": kind,
        "range_start": start.isoformat(),
        "range_end": end.isoformat(),
    }
    cached = database["insight_cache"].find_one(cache_query)
    now = datetime.now(timezone.utc)

    # 1. Reuse cache if hash matches and force is False
    if cached and not payload.force:
        cached_hash = cached.get("input_hash")
        rep_obj = cached.get("report") or cached.get("insight")
        if cached_hash == current_hash and rep_obj:
            return CachedInsightResponse(
                status="fresh",
                period=normalized_period,
                range_start=start.isoformat(),
                range_end=end.isoformat(),
                report=rep_obj,
                insight=rep_obj,
                summary=summary,
                generated_at=cached.get("generated_at"),
                input_hash=cached_hash,
                current_hash=current_hash,
                days_logged=days_logged,
                can_generate=True,
            )

        # 2. Check 10-minute cooldown if data changed but recent report exists
        last_gen = cached.get("generated_at")
        if last_gen:
            if last_gen.tzinfo is None:
                last_gen = last_gen.replace(tzinfo=timezone.utc)
            elapsed = (now - last_gen).total_seconds()
            if elapsed < 600 and rep_obj:
                return CachedInsightResponse(
                    status="stale",
                    period=normalized_period,
                    range_start=start.isoformat(),
                    range_end=end.isoformat(),
                    report=rep_obj,
                    insight=rep_obj,
                    summary=summary,
                    generated_at=cached.get("generated_at"),
                    input_hash=cached_hash,
                    current_hash=current_hash,
                    days_logged=days_logged,
                    can_generate=True,
                    warning="Regeneration cooldown active (10 minutes). Showing previous report.",
                )

    # 3. Call Gemini to generate insight
    try:
        insight, model_used = generate_period_insight(normalized_period, summary)
        report_data = insight.model_dump(mode="json")
    except Exception as e:
        # Fallback to stale cached report if Gemini fails
        rep_obj = cached.get("report") or cached.get("insight") if cached else None
        if cached and rep_obj:
            return CachedInsightResponse(
                status="stale",
                period=normalized_period,
                range_start=start.isoformat(),
                range_end=end.isoformat(),
                report=rep_obj,
                insight=rep_obj,
                summary=summary,
                generated_at=cached.get("generated_at"),
                input_hash=cached.get("input_hash"),
                current_hash=current_hash,
                days_logged=days_logged,
                can_generate=True,
                warning=f"Insight generation failed ({e}); showing previous cached report.",
            )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Insight generation failed; existing journal and statistics are unchanged.",
        ) from None

    # 4. Save to insight_cache collection
    cache_doc = {
        "user_id": user_id,
        "kind": kind,
        "range_start": start.isoformat(),
        "range_end": end.isoformat(),
        "input_hash": current_hash,
        "report": report_data,
        "prompt_version": INSIGHT_PROMPT_VERSION,
        "model": model_used,
        "generated_at": now,
    }
    database["insight_cache"].update_one(cache_query, {"$set": cache_doc}, upsert=True)

    # Also keep legacy reports collection in sync for backward compatibility
    database["reports"].update_one(
        {
            "user_id": user_id,
            "period": normalized_period,
            "period_start": start.isoformat(),
        },
        {
            "$set": {
                "period_end": end.isoformat(),
                "summary": summary,
                "insight": report_data,
                "input_hash": current_hash,
                "prompt_version": INSIGHT_PROMPT_VERSION,
                "model": model_used,
                "generated_at": now,
            }
        },
        upsert=True,
    )

    return CachedInsightResponse(
        status="fresh",
        period=normalized_period,
        range_start=start.isoformat(),
        range_end=end.isoformat(),
        report=report_data,
        insight=report_data,
        summary=summary,
        generated_at=now,
        input_hash=current_hash,
        current_hash=current_hash,
        days_logged=days_logged,
        can_generate=True,
    )