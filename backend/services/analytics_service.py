from datetime import date, datetime
from pymongo.database import Database
from backend.services.progress_engine import compute_day_totals
from backend.services.close_service import get_user_targets_snapshot


def aggregate_period(
    database: Database,
    user_id: str,
    period: str,
    start_date: date,
    end_date: date,
) -> dict:
    start_iso = start_date.isoformat()
    end_iso = end_date.isoformat()

    # Load user targets snapshot for comparison
    user = database["users"].find_one({"user_id": user_id}, {"_id": 0, "phone_number": 0})
    targets = get_user_targets_snapshot(user or {})
    target_protein = targets.get("protein_g") or 0.0

    # Query all entries for this user in the period
    entries = list(database["daily_logs"].find({
        "user_id": user_id,
        "date": {"$gte": start_iso, "$lte": end_iso},
    }).sort("timestamp", 1))

    # Group entries by date
    days_map: dict[str, list[dict]] = {}
    for entry in entries:
        d = entry.get("date")
        if d:
            days_map.setdefault(d, []).append(entry)

    # Compute daily totals for each day
    day_totals = {}
    total_protein = 0.0
    total_hydration = 0.0
    workout_days = 0
    target_met_days = 0
    eligible_target_days = 0

    for d, d_entries in days_map.items():
        totals = compute_day_totals(d_entries)
        day_totals[d] = totals

        p = totals.get("protein_g") or 0.0
        h = totals.get("hydration_ml") or 0
        w = totals.get("workout_done", False)

        total_protein += p
        total_hydration += h
        if w:
            workout_days += 1

        if target_protein > 0:
            eligible_target_days += 1
            if p >= target_protein:
                target_met_days += 1

    tracked_count = len(day_totals)
    avg_protein = (total_protein / tracked_count) if tracked_count > 0 else None
    avg_hydration = (total_hydration / tracked_count) if tracked_count > 0 else None

    # Check closed days in days collection
    closed_docs = list(database["days"].find({
        "user_id": user_id,
        "date": {"$gte": start_iso, "$lte": end_iso},
        "closed": True,
    }))
    completed_days = len(closed_docs)
    incomplete_days = max(tracked_count - completed_days, 0)

    adherence_pct = None
    if eligible_target_days > 0:
        adherence_pct = round((target_met_days / eligible_target_days) * 100, 1)

    return {
        "period": period,
        "start_date": start_iso,
        "end_date": end_iso,
        "completed_days": completed_days,
        "incomplete_days": incomplete_days,
        "average_protein_g": _rounded(avg_protein),
        "protein_target_adherence_percent": adherence_pct,
        "workout_days": workout_days,
        "average_hydration_ml": _rounded(avg_hydration),
        "tracked_days": tracked_count,
    }


def _rounded(value):
    return round(value, 2) if value is not None else None