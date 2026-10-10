import logging
import os
from datetime import datetime, timezone
import firebase_admin
from firebase_admin import credentials, messaging
from pymongo.database import Database

logger = logging.getLogger("zenlog.fcm")

# Path to service account key
SERVICE_ACCOUNT_PATH = os.environ.get(
    "FIREBASE_CREDENTIALS_PATH",
    os.path.join(os.path.dirname(os.path.dirname(__file__)), "firebase_service_account.json"),
)

_firebase_app = None


def get_firebase_app():
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    try:
        if not firebase_admin._apps:
            # 1. Check for raw JSON string in environment variable (Render production)
            json_str = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
            if json_str:
                import json
                cred_dict = json.loads(json_str)
                cred = credentials.Certificate(cred_dict)
                _firebase_app = firebase_admin.initialize_app(cred)
            # 2. Check for file path
            elif os.path.exists(SERVICE_ACCOUNT_PATH):
                cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
                _firebase_app = firebase_admin.initialize_app(cred)
            else:
                logger.warning(f"Firebase credentials not found at {SERVICE_ACCOUNT_PATH} or in FIREBASE_SERVICE_ACCOUNT_JSON")
                return None
        else:
            _firebase_app = firebase_admin.get_app()
        logger.info("Firebase Admin initialized successfully.")
        return _firebase_app
    except Exception as e:
        logger.error(f"Error initializing Firebase Admin: {e}")
        return None


def build_notification_content(template_type: str, **kwargs) -> tuple[str, str, dict]:
    """
    Constructs high-impact, beautifully formatted notification templates.
    Returns (title, body, data_payload).
    """
    if template_type == "morning_quote":
        quote = kwargs.get("quote", "We are what we repeatedly do. Excellence, then, is not an act, but a habit.")
        author = kwargs.get("author", "Aristotle")
        title = "✦ ZENLOG • MORNING INSPIRATION"
        body = f'"{quote}"\n\n— {author}'
        data = {"action": "open_quote", "template": "morning_quote"}

    elif template_type == "evening_quote":
        quote = kwargs.get("quote", "Take pride in how far you have come today. Rest well to recharge for tomorrow.")
        author = kwargs.get("author", "Marcus Aurelius")
        title = "✦ ZENLOG • EVENING REFLECTION"
        body = f'"{quote}"\n\n— {author}'
        data = {"action": "open_quote", "template": "evening_quote"}

    elif template_type == "breakfast_check":
        title = "🍳 ZENLOG • MORNING CHECK-IN"
        body = "Fuel your morning. Haven't logged breakfast yet? Tap to log in seconds."
        data = {"action": "log_meal", "meal": "breakfast"}

    elif template_type == "lunch_check":
        title = "🥗 ZENLOG • AFTERNOON FUEL"
        body = "Keep your momentum going! Take 10 seconds to record your lunch."
        data = {"action": "log_meal", "meal": "lunch"}

    elif template_type == "dinner_check":
        title = "🌙 ZENLOG • WRAP UP YOUR DAY"
        body = "1 log away from closing today. Record dinner and review your goals."
        data = {"action": "log_meal", "meal": "dinner"}

    elif template_type == "hydration_nudge":
        current = kwargs.get("current_ml", 1200)
        target = kwargs.get("target_ml", 3000)
        title = "💧 ZENLOG • HYDRATION CHECK"
        body = f"You're at {current:,} / {target:,} ml today. Grab a glass to stay energized!"
        data = {"action": "quick_water", "amount": "250"}

    elif template_type == "custom":
        label = kwargs.get("label", "Time for your daily routine")
        title = "⏰ ZENLOG • REMINDER"
        body = label
        data = {"action": "custom_reminder", "reminder_id": str(kwargs.get("id", ""))}

    elif template_type == "test":
        title = "✦ ZENLOG • TEST NOTIFICATION"
        body = "Your rich notifications are configured perfectly! Fast, calm & focused."
        data = {"action": "test", "timestamp": datetime.now(timezone.utc).isoformat()}

    else:
        title = kwargs.get("title", "ZenLog")
        body = kwargs.get("body", "Tap to open ZenLog")
        data = kwargs.get("data", {})

    return title, body, data


def send_push_to_token(token: str, template_type: str, **kwargs) -> bool:
    """Sends a formatted push notification to a specific device FCM token."""
    app = get_firebase_app()
    if not app:
        logger.warning("Cannot send push: Firebase app not initialized.")
        return False

    title, body, data = build_notification_content(template_type, **kwargs)

    try:
        android_config = messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                title=title,
                body=body,
                icon="ic_notification",
                color="#0D2115",  # ZenLog brand dark green
                channel_id="zenlog_alerts",
                sound="default",
                default_sound=True,
                default_vibrate_timings=True,
                click_action="FLUTTER_NOTIFICATION_CLICK",
                tag=template_type,
            ),
            data=data,
        )

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            android=android_config,
            token=token,
        )

        response = messaging.send(message)
        logger.info(f"FCM message sent successfully: {response}")
        return True
    except Exception as e:
        logger.error(f"Error sending FCM message to token: {e}")
        return False


def send_push_to_user(database: Database, user_id: str, template_type: str, **kwargs) -> int:
    """Sends a rich notification to all registered tokens for a user. Cleans up expired tokens."""
    tokens_cursor = database["fcm_tokens"].find({"user_id": user_id})
    tokens = [t["token"] for t in tokens_cursor if t.get("token")]

    if not tokens:
        logger.info(f"No FCM tokens found for user {user_id}")
        return 0

    success_count = 0
    stale_tokens = []

    for token in tokens:
        ok = send_push_to_token(token, template_type, **kwargs)
        if ok:
            success_count += 1
        else:
            # We can flag or remove stale tokens
            stale_tokens.append(token)

    if stale_tokens:
        database["fcm_tokens"].delete_many({"token": {"$in": stale_tokens}})

    return success_count
