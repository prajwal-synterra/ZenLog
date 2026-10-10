from datetime import date as date_type
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

try:
    IST = ZoneInfo("Asia/Kolkata")
except Exception:
    IST = timezone(timedelta(hours=5, minutes=30), name="IST")


class LogCreateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    text: str = Field(min_length=1, max_length=10000)
    client_id: str | None = None
    logged_at: datetime | None = None
    timestamp: datetime | None = None
    date: date_type | None = None
    source: str = "text"
    meta: dict | None = None

    @field_validator("logged_at", "timestamp")
    @classmethod
    def normalize_timestamp_to_ist(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=IST)
        return value.astimezone(IST)


class StructuredLogCreateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    text: str = Field(min_length=1, max_length=10000)
    extracted: dict = Field(default_factory=dict)
    client_id: str | None = None
    logged_at: datetime | None = None
    timestamp: datetime | None = None
    source: str = "structured"
    meta: dict | None = None

    @field_validator("logged_at", "timestamp")
    @classmethod
    def normalize_timestamp_to_ist(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=IST)
        return value.astimezone(IST)


class RepeatLogRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    logged_at: datetime | None = None
    timestamp: datetime | None = None
    client_id: str | None = None

    @field_validator("logged_at", "timestamp")
    @classmethod
    def normalize_timestamp_to_ist(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=IST)
        return value.astimezone(IST)


class LogUpdateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    text: str | None = Field(default=None, min_length=1, max_length=10000)
    logged_at: datetime | None = None
    timestamp: datetime | None = None
    date: date_type | None = None

    @field_validator("logged_at", "timestamp")
    @classmethod
    def normalize_timestamp_to_ist(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=IST)
        return value.astimezone(IST)

    @model_validator(mode="after")
    def require_a_change(self):
        if not self.model_fields_set:
            raise ValueError("Provide at least one field to update.")
        if not any(value is not None for value in (self.text, self.logged_at, self.timestamp, self.date)):
            raise ValueError("Provide at least one non-null field to update.")
        return self


class LogResponse(BaseModel):
    id: str
    user_id: str
    date: date_type
    logical_date: str | None = None
    timestamp: datetime
    logged_at: datetime | None = None
    time_display: str
    text: str
    source: str = "text"
    extraction_status: str = "done"
    extracted: dict | None = None
    overrides: dict | None = None
    created_at: datetime
    client_id: str | None = None