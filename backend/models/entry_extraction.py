"""Per-entry extraction schema for v2.

Each log entry is extracted individually by Gemini.
All fields are optional — a workout entry has no nutrition, a meal has no workout, etc.
"""
from typing import Literal

from pydantic import BaseModel, Field, NonNegativeFloat, NonNegativeInt


class EntryFoodItem(BaseModel):
    food: str
    quantity: str | None = None
    protein_g: NonNegativeFloat | None = None
    calories_kcal: NonNegativeFloat | None = None
    source: Literal["explicit_user_value", "estimated", "unknown"] = "unknown"
    confidence: Literal["high", "medium", "low", "unknown"] = "unknown"


class EntryNutrition(BaseModel):
    meal_type: Literal["breakfast", "lunch", "dinner", "snack"] | None = None
    items: list[EntryFoodItem] = Field(default_factory=list)
    # Backend recomputes these from items; model values are advisory only
    protein_g: NonNegativeFloat | None = None
    calories_kcal: NonNegativeFloat | None = None


class EntryWorkout(BaseModel):
    type: str
    duration_mins: NonNegativeInt | None = None
    intensity: str | None = None
    exercises: list[str] = Field(default_factory=list)


class EntryLearning(BaseModel):
    activity: str
    book: str | None = None
    pages: NonNegativeInt | None = None
    duration_mins: NonNegativeInt | None = None


class EntryHabit(BaseModel):
    habit: str
    completed: bool | None = None


class EntryMood(BaseModel):
    mood: str
    context: str | None = None


class GoalAlignment(BaseModel):
    rating: Literal["good", "neutral", "poor", "not_applicable"] = "not_applicable"
    reason: str | None = None
    quality_flags: list[
        Literal[
            "whole_food", "high_protein", "high_fiber", "fried", "sugary",
            "processed", "alcohol", "skipped_meal", "large_portion", "light_meal",
        ]
    ] = Field(default_factory=list)


class EntryExtraction(BaseModel):
    """Structured extraction for one journal log entry."""
    nutrition: EntryNutrition | None = None
    hydration_ml: NonNegativeInt | None = None
    workout: EntryWorkout | None = None
    learning: EntryLearning | None = None
    habits: list[EntryHabit] = Field(default_factory=list)
    mood: EntryMood | None = None
    goal_alignment: GoalAlignment = Field(default_factory=GoalAlignment)
