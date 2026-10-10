from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

from backend.core.security import hash_pin, verify_pin
from backend.models.profile import ProfileResponse, ProfileUpdateRequest, SetPinRequest
from backend.routes.dependencies import get_auth_context, get_database


router = APIRouter(prefix="/api/users", tags=["users"])


@router.get("/me", response_model=ProfileResponse)
def get_current_user(
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user = database["users"].find_one(
        {"user_id": auth_context["user"]["user_id"]},
        {"_id": 0, "phone_number": 0, "phone": 0},
    )
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    user["has_pin"] = bool(user.get("pin") or user.get("pin_hash"))
    return user


@router.put("/me", response_model=ProfileResponse)
def update_current_user(
    payload: ProfileUpdateRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    changes = payload.model_dump(exclude_unset=True, exclude_none=True)
    if not changes:
        raise HTTPException(status_code=422, detail="Provide at least one profile field.")
    database["users"].update_one(
        {"user_id": auth_context["user"]["user_id"]},
        {"$set": {**changes, "updated_at": datetime.now(timezone.utc)}},
    )
    res = database["users"].find_one(
        {"user_id": auth_context["user"]["user_id"]},
        {"_id": 0, "phone_number": 0, "phone": 0},
    )
    if res:
        res["has_pin"] = bool(res.get("pin") or res.get("pin_hash"))
    return res


@router.put("/pin")
def set_or_change_pin(
    payload: SetPinRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    user = database["users"].find_one({"user_id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    current_pin_val = user.get("pin") or user.get("pin_hash")
    if current_pin_val:
        if not payload.current_pin:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Current PIN is required to change your PIN.",
            )
        if not verify_pin(payload.current_pin, current_pin_val):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Current PIN is incorrect.",
            )

    plain_pin = str(payload.pin).strip()
    database["users"].update_one(
        {"user_id": user_id},
        {"$set": {"pin": plain_pin, "pin_hash": plain_pin, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"ok": True, "detail": "PIN configured successfully.", "has_pin": True}