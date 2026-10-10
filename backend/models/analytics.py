from datetime import date, datetime

from pydantic import BaseModel

from backend.models.extraction import InsightReport


class CalendarDay(BaseModel):
    date: date
    status: str
    protein_g: float | None = None
    protein_target_g: float | None = None
    workout: bool = False


class DailyStatsResponse(BaseModel):
    date: date
    status: str
    log_count: int
    protein_g: float | None = None
    protein_target_g: float | None = None
    target_percentage: float | None = None
    remaining_protein_g: float | None = None
    hydration_ml: int | None = None
    workout: bool


class PeriodStatsResponse(BaseModel):
    period: str
    start_date: date
    end_date: date
    completed_days: int
    incomplete_days: int
    average_protein_g: float | None = None
    protein_target_adherence_percent: float | None = None
    workout_days: int
    average_hydration_ml: float | None = None
    average_sleep_hours: float | None = None
    average_sleep_minutes: int | None = None


class InsightResponse(BaseModel):
    report_id: str
    period: str
    period_start: date
    period_end: date
    generated_at: datetime
    summary: dict
    insight: InsightReport


class CachedInsightResponse(BaseModel):
    status: str  # "fresh" | "stale" | "none"
    period: str
    range_start: str
    range_end: str
    report: dict | None = None
    insight: dict | None = None
    summary: dict = {}
    generated_at: datetime | None = None
    input_hash: str | None = None
    current_hash: str
    days_logged: int = 0
    can_generate: bool = False
    warning: str | None = None


class GenerateInsightRequest(BaseModel):
    force: bool = False
    anchor: date | None = None


class DayVerdictResponse(BaseModel):
    status: str  # "fresh" | "stale" | "none"
    day: str
    verdict: dict | None = None
    generated_at: datetime | None = None
    input_hash: str | None = None
    current_hash: str
    can_generate: bool = True
    warning: str | None = None


class DayVerdictGenerateRequest(BaseModel):
    force: bool = False