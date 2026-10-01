from datetime import date as date_type
from datetime import datetime, timedelta, timezone

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


IST = timezone(timedelta(hours=5, minutes=30), name="IST")


class LogCreateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    text: str = Field(min_length=1, max_length=10000)
    client_id: str | None = None
    date: date_type | None = None
    timestamp: datetime | None = None

    @field_validator("timestamp")
    @classmethod
    def normalize_timestamp_to_ist(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=IST)
        return value.astimezone(IST)

    @model_validator(mode="after")
    def date_matches_timestamp(self):
        if self.date is not None and self.timestamp is not None:
            if self.timestamp.date() != self.date:
                raise ValueError("date must match the timestamp's date in IST.")
        return self


class LogUpdateRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    text: str | None = Field(default=None, min_length=1, max_length=10000)
    date: date_type | None = None
    timestamp: datetime | None = None

    @field_validator("timestamp")
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
        if not any(value is not None for value in (self.text, self.date, self.timestamp)):
            raise ValueError("Provide at least one non-null field to update.")
        if self.date and self.timestamp and self.timestamp.date() != self.date:
            raise ValueError("date must match the timestamp's date in IST.")
        return self


class LogResponse(BaseModel):
    id: str
    user_id: str
    date: date_type
    timestamp: datetime
    time_display: str
    text: str
    created_at: datetime
    client_id: str | None = None