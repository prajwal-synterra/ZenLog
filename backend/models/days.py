from datetime import date

from pydantic import BaseModel, ConfigDict, Field

from backend.models.log import LogResponse


class SleepRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    sleep_time: str = Field(pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")


class WakeRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    wake_time: str = Field(pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")


class EditSleepRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    sleep_time: str = Field(pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")
    reprocess: bool = False


class ReprocessDayRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    sleep_time: str | None = Field(default=None, pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")


class DailyRecordResponse(BaseModel):
    record_id: str
    user_id: str
    date: date
    schema_version: str
    status: str
    sleep: dict = {}
    wake: dict = {}
    nutrition: dict = {}
    fitness: dict = {}
    learning: dict = {}
    habits: dict = {}
    mood: dict = {}
    insights: dict = {}
    processing: dict = {}


class DailyHistoryResponse(BaseModel):
    date: date
    status: str
    logs: list[LogResponse]
    record: DailyRecordResponse | None = None


class DayPromptStatusResponse(BaseModel):
    today: date
    yesterday: date
    needs_yesterday_sleep: bool
    needs_today_wake: bool
    yesterday_status: str
    today_status: str
    yesterday_sleep_time: str | None = None
    today_wake_time: str | None = None