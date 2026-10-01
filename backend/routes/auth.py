import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

from backend.models.auth import LoginRequest, LoginResponse, LogoutResponse, UserResponse
from backend.routes.dependencies import get_auth_context, get_database


router = APIRouter(prefix="/api/auth", tags=["auth"])

# Long-lived rolling session: 180 days
SESSION_DURATION = timedelta(days=180)
SESSION_ROLLING_THRESHOLD = timedelta(days=1)


@router.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest, database: Database = Depends(get_database)):
    user = database["users"].find_one(
        {"username": payload.username, "phone_number": payload.phone_number},
        {"_id": 0},
    )
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or phone number.",
        )

    now = datetime.now(timezone.utc)
    token = secrets.token_urlsafe(48)
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    expires_at = now + SESSION_DURATION

    device_id = getattr(payload, "device_id", None) or "default"

    # One session per (user, device_id): replace old session from same device
    database["sessions"].delete_many({
        "user_id": user["user_id"],
        "device_id": device_id,
    })
    database["sessions"].insert_one({
        "token_hash": token_hash,
        "user_id": user["user_id"],
        "device_id": device_id,
        "device_name": getattr(payload, "device_name", None),
        "created_at": now,
        "last_used_at": now,
        "expires_at": expires_at,
        "revoked": False,
        "revoked_at": None,
    })

    return LoginResponse(
        access_token=token,
        expires_at=expires_at,
        user=UserResponse(
            user_id=user["user_id"],
            username=user["username"],
            name=user["name"],
        ),
    )


@router.get("/me")
def get_me(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Cheap token validity check + rolling session refresh. Called on app start."""
    user = auth_context["user"]
    token_hash = auth_context["token_hash"]
    now = datetime.now(timezone.utc)

    # Rolling refresh: push expiry forward if last_used is older than 1 day
    session = database["sessions"].find_one({"token_hash": token_hash})
    if session:
        last_used = session.get("last_used_at", now)
        if (now - last_used) > SESSION_ROLLING_THRESHOLD:
            new_expires = now + SESSION_DURATION
            database["sessions"].update_one(
                {"token_hash": token_hash},
                {"$set": {"last_used_at": now, "expires_at": new_expires}},
            )

    from backend.models.log import IST
    from datetime import date as date_type
    logical_today = datetime.now(IST)
    if logical_today.hour < 4:
        from datetime import timedelta as td
        logical_today = (logical_today - td(hours=4)).date()
    else:
        logical_today = logical_today.date()

    return {
        "user_id": user.get("user_id"),
        "username": user.get("username"),
        "name": user.get("name"),
        "goal": user.get("goal"),
        "daily_protein_target_g": user.get("daily_protein_target_g"),
        "daily_calorie_target": user.get("daily_calorie_target"),
        "daily_water_target_ml": user.get("daily_water_target_ml", 3000),
        "weekly_workout_target": user.get("weekly_workout_target", 3),
        "body_weight_kg": user.get("body_weight_kg"),
        "logical_today": logical_today.isoformat(),
    }


@router.post("/logout", response_model=LogoutResponse)
def logout(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    database["sessions"].update_one(
        {"token_hash": auth_context["token_hash"], "revoked": {"$ne": True}},
        {"$set": {"revoked": True, "revoked_at": datetime.now(timezone.utc)}},
    )
    return LogoutResponse(detail="Logged out successfully.")