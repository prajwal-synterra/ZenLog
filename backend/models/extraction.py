from typing import Literal

from pydantic import BaseModel, Field, NonNegativeFloat, NonNegativeInt


class ExtractedFood(BaseModel):
    food: str
    quantity: str | None = None
    protein_g: NonNegativeFloat | None = None
    calories_kcal: NonNegativeFloat | None = None
    protein_source: Literal["explicit_user_value", "estimated", "unknown"] = "unknown"
    confidence: Literal["high", "medium", "low", "unknown"] = "unknown"


class ExtractedMeal(BaseModel):
    meal: str
    items: list[ExtractedFood] = Field(default_factory=list)


class NutritionExtraction(BaseModel):
    meals: list[ExtractedMeal] = Field(default_factory=list)
    water_intake_ml: list[NonNegativeInt] = Field(default_factory=list)


class WorkoutExtraction(BaseModel):
    type: str
    duration_mins: NonNegativeInt | None = None
    intensity: str | None = None
    exercises: list[str] = Field(default_factory=list)


class LearningActivity(BaseModel):
    activity: str
    book: str | None = None
    pages: NonNegativeInt | None = None
    duration_mins: NonNegativeInt | None = None


class HabitObservation(BaseModel):
    habit: str
    completed: bool | None = None


class MoodObservation(BaseModel):
    mood: str
    context: str | None = None


class DailyInsights(BaseModel):
    growth_wins: list[str] = Field(default_factory=list)
    areas_to_improve: list[str] = Field(default_factory=list)
    coaching_notes: str = ""


class DailyExtraction(BaseModel):
    nutrition: NutritionExtraction = Field(default_factory=NutritionExtraction)
    workouts: list[WorkoutExtraction] = Field(default_factory=list)
    learning: list[LearningActivity] = Field(default_factory=list)
    habits: list[HabitObservation] = Field(default_factory=list)
    moods: list[MoodObservation] = Field(default_factory=list)
    insights: DailyInsights = Field(default_factory=DailyInsights)


class InsightReport(BaseModel):
    summary: str
    highlights: list[str] = Field(default_factory=list)
    areas_to_improve: list[str] = Field(default_factory=list)
    coaching_notes: str = ""