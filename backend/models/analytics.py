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