import asyncio
import logging
from datetime import datetime, timezone
from pymongo.database import Database
from backend.models.log import IST
from backend.services.fcm_service import send_push_to_user

logger = logging.getLogger("zenlog.scheduler")

_sent_cache = set()
_last_cleared_date = None


async def notification_scheduler_loop(database: Database):
    """
    Background worker running on the backend every 30 seconds.
    Dispatches:
    - 07:00 IST: Morning Inspiration Quote
    - 19:00 IST: Evening Reflection Quote
    - 11:00 IST: Breakfast check (if unlogged)
    - 15:00 IST: Lunch check (if unlogged)
    - 22:00 IST: Dinner check (if unlogged)
    - User custom reminders matching current HH:MM IST
    """
    global _sent_cache, _last_cleared_date
    logger.info("ZenLog Notification Scheduler Loop active.")

    while True:
        try:
            now_ist = datetime.now(IST)
            today_str = now_ist.strftime("%Y-%m-%d")
            time_str = now_ist.strftime("%H:%M")  # e.g. "08:30", "23:05"

            # Reset daily cache at midnight IST
            if _last_cleared_date != today_str:
                _sent_cache.clear()
                _last_cleared_date = today_str

            # Query all users with configured notifications
            users = list(database["users"].find({"notification_settings": {"$exists": True}}))

            for user in users:
                user_id = user["user_id"]
                settings = user.get("notification_settings") or {}

                # 1. 7 AM Morning Quote
                if time_str == "07:00" and settings.get("morning_quote", True):
                    cache_key = f"{user_id}_morning_quote_{today_str}"
                    if cache_key not in _sent_cache:
                        _sent_cache.add(cache_key)
                        send_push_to_user(database, user_id, "morning_quote")

                # 2. 7 PM Evening Quote
                if time_str == "19:00" and settings.get("evening_quote", True):
                    cache_key = f"{user_id}_evening_quote_{today_str}"
                    if cache_key not in _sent_cache:
                        _sent_cache.add(cache_key)
                        send_push_to_user(database, user_id, "evening_quote")

                # 3. 11 AM Breakfast Check
                if time_str == "11:00" and settings.get("breakfast_reminder", True):
                    cache_key = f"{user_id}_breakfast_{today_str}"
                    if cache_key not in _sent_cache:
                        _sent_cache.add(cache_key)
                        _check_meal_and_send(database, user_id, today_str, "breakfast", "breakfast_check")

                # 4. 3 PM Lunch Check
                if time_str == "15:00" and settings.get("lunch_reminder", True):
                    cache_key = f"{user_id}_lunch_{today_str}"
                    if cache_key not in _sent_cache:
                        _sent_cache.add(cache_key)
                        _check_meal_and_send(database, user_id, today_str, "lunch", "lunch_check")

                # 5. 10 PM Dinner Check
                if time_str == "22:00" and settings.get("dinner_reminder", True):
                    cache_key = f"{user_id}_dinner_{today_str}"
                    if cache_key not in _sent_cache:
                        _sent_cache.add(cache_key)
                        _check_meal_and_send(database, user_id, today_str, "dinner", "dinner_check")

                # 6. Custom Reminders matching current time
                custom_list = settings.get("custom_reminders") or []
                for reminder in custom_list:
                    if reminder.get("enabled", True):
                        rem_time = (reminder.get("time") or "").strip()
                        rem_id = str(reminder.get("id") or reminder.get("label") or "")
                        if rem_time == time_str:
                            cache_key = f"{user_id}_custom_{rem_id}_{today_str}_{time_str}"
                            if cache_key not in _sent_cache:
                                _sent_cache.add(cache_key)
                                label = reminder.get("label") or "ZenLog Reminder"
                                send_push_to_user(
                                    database,
                                    user_id,
                                    "custom",
                                    label=label,
                                    id=rem_id,
                                )

        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Error in notification scheduler loop: {e}")

        await asyncio.sleep(30)


def _check_meal_and_send(database: Database, user_id: str, date_str: str, meal_name: str, template: str):
    try:
        logs = list(database["daily_logs"].find({"user_id": user_id, "date": date_str}))
        logged = False
        for log in logs:
            text = (log.get("text") or "").lower()
            extracted = log.get("extracted") or {}
            mtype = extracted.get("meal_type") or ""
            if meal_name in text or mtype == meal_name:
                logged = True
                break
        if not logged:
            send_push_to_user(database, user_id, template)
    except Exception as e:
        logger.error(f"Error checking meal {meal_name} for user {user_id}: {e}")
