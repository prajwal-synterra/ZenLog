from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pymongo.database import Database

from backend.models.profile import ProfileResponse, ProfileUpdateRequest
from backend.routes.dependencies import get_auth_context, get_database


router = APIRouter(prefix="/api/users", tags=["users"])


@router.get("/me", response_model=ProfileResponse)
def get_current_user(auth_context: dict = Depends(get_auth_context)):
    return auth_context["user"]


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
    return database["users"].find_one(
        {"user_id": auth_context["user"]["user_id"]},
        {"_id": 0, "phone_number": 0, "phone": 0},
    )