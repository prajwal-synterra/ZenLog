from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from pymongo.database import Database

from backend.routes.dependencies import get_auth_context, get_database
from backend.services.fcm_service import send_push_to_user


router = APIRouter(prefix="/api/notifications", tags=["notifications"])


class RegisterTokenRequest(BaseModel):
    fcm_token: str = Field(min_length=10)
    device_id: str | None = None
    platform: str = "android"


class CustomReminder(BaseModel):
    id: str
    time: str = Field(pattern=r"^\d{2}:\d{2}$")  # "HH:MM" e.g. "08:30"
    label: str = Field(min_length=1, max_length=100)
    enabled: bool = True


class NotificationSettingsRequest(BaseModel):
    breakfast_reminder: bool = True  # 11:00 AM
    lunch_reminder: bool = True      # 03:00 PM
    dinner_reminder: bool = True     # 10:00 PM
    morning_quote: bool = True       # 07:00 AM
    evening_quote: bool = True       # 07:00 PM
    hydration_reminder: bool = True  # 04:00 PM
    custom_reminders: list[CustomReminder] = []


DEFAULT_NOTIFICATION_SETTINGS = {
    "breakfast_reminder": True,
    "lunch_reminder": True,
    "dinner_reminder": True,
    "morning_quote": True,
    "evening_quote": True,
    "hydration_reminder": True,
    "custom_reminders": [],
}


@router.post("/register-token")
def register_fcm_token(
    payload: RegisterTokenRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    device_id = payload.device_id or "default"
    now = datetime.now(timezone.utc)

    database["fcm_tokens"].update_one(
        {"user_id": user_id, "device_id": device_id},
        {
            "$set": {
                "user_id": user_id,
                "device_id": device_id,
                "token": payload.fcm_token.strip(),
                "platform": payload.platform,
                "updated_at": now,
            }
        },
        upsert=True,
    )
    return {"ok": True, "detail": "FCM token registered successfully."}


@router.get("/settings")
def get_notification_settings(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user = database["users"].find_one({"user_id": auth_context["user"]["user_id"]})
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    settings = user.get("notification_settings") or DEFAULT_NOTIFICATION_SETTINGS
    return {"ok": True, "settings": settings}


@router.put("/settings")
def update_notification_settings(
    payload: NotificationSettingsRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    database["users"].update_one(
        {"user_id": user_id},
        {"$set": {"notification_settings": payload.model_dump(), "updated_at": datetime.now(timezone.utc)}},
    )
    return {"ok": True, "settings": payload.model_dump()}


@router.post("/test")
def trigger_test_notification(
    template: str = Query(default="test", pattern="^(test|morning_quote|evening_quote|breakfast_check|lunch_check|dinner_check|hydration_nudge)$"),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Sends an immediate test notification with the selected rich template to the caller's device."""
    user = auth_context["user"]
    user_id = user["user_id"]

    sent_count = send_push_to_user(database, user_id, template_type=template)
    if sent_count == 0:
        return {
            "ok": False,
            "detail": "No registered device token found. Open ZenLog on your phone to register token.",
        }

    return {
        "ok": True,
        "detail": f"Sent rich '{template}' notification to {sent_count} device(s).",
        "sent_count": sent_count,
    }


@router.post("/check-meals")
def check_meals_and_notify(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Evaluates if today's breakfast, lunch, or dinner have been logged.
    If unlogged, dispatches the appropriate rich reminder.
    """
    from backend.models.log import IST
    now_ist = datetime.now(IST)
    user = auth_context["user"]
    user_id = user["user_id"]

    # Calculate logical today date
    if now_ist.hour < 4:
        from datetime import timedelta
        today_date = (now_ist - timedelta(hours=4)).date().isoformat()
    else:
        today_date = now_ist.date().isoformat()

    # Fetch today's logs
    logs = list(database["daily_logs"].find({"user_id": user_id, "date": today_date}))

    # Classify logged meals
    has_breakfast = False
    has_lunch = False
    has_dinner = False

    for log in logs:
        text = (log.get("text") or "").lower()
        extracted = log.get("extracted") or {}
        meal_type = extracted.get("meal_type") or ""

        if "breakfast" in text or meal_type == "breakfast":
            has_breakfast = True
        if "lunch" in text or meal_type == "lunch":
            has_lunch = True
        if "dinner" in text or meal_type == "dinner":
            has_dinner = True

    # Determine what to notify based on current hour
    current_hour = now_ist.hour
    sent_template = None

    if current_hour >= 11 and current_hour < 15 and not has_breakfast:
        sent_template = "breakfast_check"
    elif current_hour >= 15 and current_hour < 20 and not has_lunch:
        sent_template = "lunch_check"
    elif current_hour >= 20 and not has_dinner:
        sent_template = "dinner_check"

    if sent_template:
        count = send_push_to_user(database, user_id, sent_template)
        return {"ok": True, "reminded": True, "template": sent_template, "sent_count": count}

    return {"ok": True, "reminded": False, "detail": "All scheduled meals for this window are already logged."}
