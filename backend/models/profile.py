from pydantic import BaseModel, ConfigDict, Field


class ProfileUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    name: str | None = Field(default=None, min_length=1, max_length=100)
    goal: str | None = Field(default=None, min_length=1, max_length=80)
    body_weight_kg: float | None = Field(default=None, gt=0, le=500)
    daily_protein_target_g: float | None = Field(default=None, gt=0, le=1000)
    daily_calorie_target: float | None = Field(default=None, gt=0, le=20000)
    daily_water_target_ml: int | None = Field(default=None, gt=0, le=20000)
    weekly_workout_target: int | None = Field(default=None, ge=0, le=14)
    sleep_target_hours: float | None = Field(default=None, gt=0, le=24)
    eating_window: dict | None = None


class ProfileResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    user_id: str
    username: str
    name: str
    goal: str | None = None
    body_weight_kg: float | None = None
    daily_protein_target_g: float | None = None
    daily_calorie_target: float | None = None
    daily_water_target_ml: int | None = None
    weekly_workout_target: int | None = None
    sleep_target_hours: float | None = None
    eating_window: dict | None = None