from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pymongo.database import Database

from backend.models.log import IST
from backend.routes.dependencies import get_auth_context, get_database
from backend.services.progress_engine import compute_day_totals


router = APIRouter(prefix="/api/calendar", tags=["calendar"])

DAY_CUTOFF_HOURS = 4


def _logical_today() -> date:
    now_ist = datetime.now(IST)
    if now_ist.hour < DAY_CUTOFF_HOURS:
        from datetime import timedelta
        return (now_ist - timedelta(hours=DAY_CUTOFF_HOURS)).date()
    return now_ist.date()


@router.get("")
def get_calendar(
    from_date: date = Query(alias="from"),
    to_date: date = Query(alias="to"),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    if from_date > to_date:
        raise HTTPException(status_code=422, detail="from must be on or before to.")

    user_id = auth_context["user"]["user_id"]
    today = _logical_today()

    period_filter = {
        "user_id": user_id,
        "date": {"$gte": from_date.isoformat(), "$lte": to_date.isoformat()},
    }

    # Load v2 days docs
    days_docs = {d["date"]: d for d in database["days"].find(period_filter)}

    # Find all dates that have logs
    dates_with_logs = set(database["daily_logs"].distinct("date", period_filter))

    # Find log counts per day
    log_counts = {}
    for doc in database["daily_logs"].aggregate([
        {"$match": period_filter},
        {"$group": {"_id": "$date", "count": {"$sum": 1}}},
    ]):
        log_counts[doc["_id"]] = doc["count"]

    # Build result for each date in range
    results = []
    current = from_date
    while current <= to_date:
        day_key = current.isoformat()
        if current > today:
            mode = "future"
        elif current == today:
            mode = "today"
        else:
            mode = "past"

        day_doc = days_docs.get(day_key)
        logs_count = log_counts.get(day_key, 0)

        if mode == "future":
            results.append({
                "date": day_key,
                "mode": "future",
                "logs_count": 0,
                "score": None,
                "rating": None,
                "status": "future",
                "protein_g": None,
                "protein_target_g": None,
                "workout": False,
            })
        elif logs_count == 0:
            results.append({
                "date": day_key,
                "mode": mode,
                "logs_count": 0,
                "score": None,
                "rating": "insufficient_data",
                "status": "no_logs",
                "protein_g": None,
                "protein_target_g": None,
                "workout": False,
            })
        else:
            # Compute live totals from entries
            entries = list(database["daily_logs"].find(
                {"user_id": user_id, "date": day_key}
            ))
            totals = compute_day_totals(entries)

            score = day_doc.get("score") if day_doc else None
            rating = day_doc.get("rating") if day_doc else None
            is_closed = bool(day_doc and day_doc.get("closed"))
            status = "closed" if is_closed else ("open" if mode == "today" else "incomplete")

            user = auth_context["user"]
            protein_target = user.get("daily_protein_target_g")

            results.append({
                "date": day_key,
                "mode": mode,
                "logs_count": logs_count,
                "score": score,
                "rating": rating or ("insufficient_data" if not is_closed else None),
                "status": status,
                "protein_g": totals.get("protein_g"),
                "protein_target_g": protein_target,
                "workout": totals.get("workout_done", False),
                "hydration_ml": totals.get("hydration_ml"),
            })

        from datetime import timedelta
        current += timedelta(days=1)

    return results