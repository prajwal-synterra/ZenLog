from datetime import datetime
from pydantic import BaseModel, Field


class ProductMeta(BaseModel):
    name: str = Field(default="Packaged Food", description="Product name")
    brand: str = Field(default="", description="Brand name if visible")
    pack_size_g: float | None = Field(default=None, description="Net weight / pack size in grams or ml")
    serving_size_g: float | None = Field(default=None, description="Single serving size in grams or ml")
    servings_per_pack: float | None = Field(default=None, description="Servings per pack")
    is_liquid: bool = Field(default=False, description="True if product is a beverage/liquid (ml)")


class NutritionValues(BaseModel):
    energy_kcal: float | None = Field(default=None, description="Energy in kcal")
    protein_g: float | None = Field(default=None, description="Protein in grams")
    carbs_g: float | None = Field(default=None, description="Total carbohydrates in grams")
    sugar_g: float | None = Field(default=None, description="Total sugars in grams")
    added_sugar_g: float | None = Field(default=None, description="Added sugars in grams")
    fat_g: float | None = Field(default=None, description="Total fat in grams")
    sat_fat_g: float | None = Field(default=None, description="Saturated fat in grams")
    trans_fat_g: float | None = Field(default=None, description="Trans fat in grams")
    fiber_g: float | None = Field(default=None, description="Dietary fiber in grams")
    sodium_mg: float | None = Field(default=None, description="Sodium in milligrams")


class ValidationResult(BaseModel):
    ok: bool = True
    warnings: list[str] = Field(default_factory=list)
    missing: list[str] = Field(default_factory=list)


class ScoreBreakdown(BaseModel):
    value: int = Field(default=50, ge=0, le=100)
    grade: str = Field(default="Okay", description="Great | Okay | Occasional | Skip")
    reasons: list[str] = Field(default_factory=list, description="Top positive and negative contributors")
    breakdown: dict[str, float] = Field(default_factory=dict)


class ScanResultResponse(BaseModel):
    scan_id: str
    product: ProductMeta
    per_100g: NutritionValues
    per_serving: NutritionValues | None = None
    ingredients: list[str] = Field(default_factory=list)
    flags: list[str] = Field(default_factory=list)
    validation: ValidationResult
    score: ScoreBreakdown
    confidence: float = 0.8
    ocr_source: str = "gemini_vision"  # "local_ocr" | "gemini_vision"


class UpdateScanRequest(BaseModel):
    product: ProductMeta | None = None
    per_100g: NutritionValues | None = None
    serving_size_g: float | None = None
    ingredients: list[str] | None = None


class EvaluateScanRequest(BaseModel):
    servings: float | None = None
    grams: float | None = None


class EvaluateScanResponse(BaseModel):
    scan_id: str
    amount_description: str
    portion_macros: dict
    day_impact: dict


class ScanLogRequest(BaseModel):
    servings: float | None = None
    grams: float | None = None
    logged_at: datetime | None = None
    client_id: str | None = None


class SaveProductRequest(BaseModel):
    scan_id: str | None = None
    name: str | None = None
    brand: str | None = None
    pack_size_g: float | None = None
    serving_size_g: float | None = None
    per_100g: NutritionValues | None = None
    ingredients: list[str] | None = None


class ProductResponse(BaseModel):
    id: str
    name: str
    brand: str = ""
    name_key: str
    pack_size_g: float | None = None
    serving_size_g: float | None = None
    per_100g: NutritionValues
    ingredients: list[str] = Field(default_factory=list)
    flags: list[str] = Field(default_factory=list)
    score: int = 50
    grade: str = "Okay"
    times_logged: int = 0
    created_at: datetime | None = None


class ProductLogRequest(BaseModel):
    servings: float | None = None
    grams: float | None = None
    logged_at: datetime | None = None
    client_id: str | None = None
