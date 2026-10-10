import csv
import io
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Query, Response
from fastapi.responses import JSONResponse
from pymongo.database import Database

from backend.routes.dependencies import get_auth_context, get_database


router = APIRouter(prefix="/api/export", tags=["export"])


def _serialize_doc(doc: dict) -> dict:
    res = {}
    for k, v in doc.items():
        if k in ("_id", "pin_hash"):
            if k == "_id":
                res["id"] = str(v)
            continue
        if isinstance(v, datetime):
            res[k] = v.isoformat()
        elif isinstance(v, dict):
            res[k] = _serialize_doc(v)
        elif isinstance(v, list):
            res[k] = [(_serialize_doc(item) if isinstance(item, dict) else item) for item in v]
        else:
            res[k] = v
    return res


@router.get("")
def export_user_data(
    format: str = Query(default="json", pattern="^(json|csv)$"),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Exports all data owned by the authenticated caller.
    format=json: streams structured JSON containing logs, days, sleep/wake, profile, saved meals.
    format=csv: streams CSV containing all food/hydration/workout logs.
    """
    user = auth_context["user"]
    user_id = user["user_id"]
    now = datetime.now(timezone.utc)
    date_slug = now.strftime("%Y-%m-%d")

    # 1. Fetch user's logs
    logs_raw = list(
        database["daily_logs"]
        .find({"user_id": user_id})
        .sort([("date", 1), ("timestamp", 1)])
    )

    if format == "csv":
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow([
            "id",
            "date",
            "logged_at",
            "text",
            "protein_g",
            "calories_kcal",
            "hydration_ml",
            "workout",
            "source",
            "extraction_status",
        ])

        for log in logs_raw:
            extracted = log.get("extracted") or {}
            nutrition = extracted.get("nutrition") or {}
            overrides = log.get("overrides") or {}
            workout = extracted.get("workout")

            protein = overrides.get("protein_g", nutrition.get("protein_g", ""))
            calories = overrides.get("calories_kcal", nutrition.get("calories_kcal", ""))
            hydration = overrides.get("hydration_ml", extracted.get("hydration_ml", ""))
            workout_str = workout.get("activity", "") if isinstance(workout, dict) else ""

            logged_at_dt = log.get("logged_at") or log.get("timestamp")
            logged_at_str = logged_at_dt.isoformat() if isinstance(logged_at_dt, datetime) else str(logged_at_dt or "")

            writer.writerow([
                str(log.get("_id") or ""),
                log.get("date", ""),
                logged_at_str,
                log.get("text", ""),
                protein,
                calories,
                hydration,
                workout_str,
                log.get("source", "text"),
                log.get("extraction_status", ""),
            ])

        csv_data = output.getvalue()
        return Response(
            content=csv_data,
            media_type="text/csv",
            headers={
                "Content-Disposition": f'attachment; filename="zenlog_logs_{user_id}_{date_slug}.csv"'
            },
        )

    # JSON format: complete export
    days_raw = list(database["days"].find({"user_id": user_id}).sort("date", 1))
    saved_meals_raw = list(database["saved_meals"].find({"user_id": user_id}))
    daily_records_raw = list(database["daily_records"].find({"user_id": user_id}).sort("date", 1))

    export_payload = {
        "version": "1.0",
        "exported_at": now.isoformat(),
        "user": {
            "user_id": user.get("user_id"),
            "username": user.get("username"),
            "name": user.get("name"),
            "goal": user.get("goal"),
            "daily_protein_target_g": user.get("daily_protein_target_g"),
            "daily_calorie_target": user.get("daily_calorie_target"),
            "daily_water_target_ml": user.get("daily_water_target_ml"),
            "weekly_workout_target": user.get("weekly_workout_target"),
            "body_weight_kg": user.get("body_weight_kg"),
        },
        "logs": [_serialize_doc(l) for l in logs_raw],
        "days": [_serialize_doc(d) for d in days_raw],
        "sleep_wake_cycles": [_serialize_doc(r) for r in daily_records_raw],
        "saved_meals": [_serialize_doc(m) for m in saved_meals_raw],
    }

    return JSONResponse(
        content=export_payload,
        headers={
            "Content-Disposition": f'attachment; filename="zenlog_export_{user_id}_{date_slug}.json"'
        },
    )
