from pydantic import BaseModel, Field


class PhotoMealItem(BaseModel):
    name: str = Field(description="Name of the food item")
    portion: str = Field(description="Portion estimate in common household units, e.g., '1 cup (~150g)' or '2 rotis'")
    protein_g: float = Field(default=0.0, description="Estimated protein in grams")
    calories: int = Field(default=0, description="Estimated energy in kcal")
    confidence: float = Field(default=0.8, description="Confidence score between 0.0 and 1.0")


class PhotoMealTotal(BaseModel):
    protein_g: float = Field(default=0.0)
    calories: int = Field(default=0)


class PhotoMealDraftResponse(BaseModel):
    items: list[PhotoMealItem] = Field(default_factory=list, description="List of recognized food items on the plate")
    total: PhotoMealTotal = Field(default_factory=PhotoMealTotal, description="Total protein and calories for the plate")
    notes: str = Field(default="", description="Observations about portion, cooking method or oil uncertainty")
    estimate: bool = Field(default=True, description="Always true indicating photo estimation")
