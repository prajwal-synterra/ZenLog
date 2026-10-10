from datetime import datetime
from typing import Any
from pydantic import BaseModel, Field


class SavedMealCreateRequest(BaseModel):
    log_id: str | None = None
    name: str | None = None
    raw_text: str | None = None
    extracted: dict[str, Any] | None = None
    pinned: bool = False


class SavedMealUpdateRequest(BaseModel):
    name: str | None = None
    raw_text: str | None = None
    extracted: dict[str, Any] | None = None
    pinned: bool | None = None


class SavedMealLogRequest(BaseModel):
    portion: float = Field(default=1.0, gt=0, le=20.0)
    logged_at: datetime | None = None
    client_id: str | None = None


class SavedMealResponse(BaseModel):
    id: str
    user_id: str
    name: str
    raw_text: str
    extracted: dict[str, Any]
    use_count: int = 0
    last_used_at: datetime | None = None
    pinned: bool = False
    created_from_log_id: str | None = None
    created_at: datetime
    updated_at: datetime


class SavedMealSuggestion(BaseModel):
    name: str
    raw_text: str
    count: int
    sample_log_id: str
    sample_extracted: dict[str, Any]
