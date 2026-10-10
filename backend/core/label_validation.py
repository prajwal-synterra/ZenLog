from backend.models.food_scan import NutritionValues, ValidationResult


def validate_nutrition(n: NutritionValues) -> ValidationResult:
    """
    Sanity checks for packaged food nutrition labels (Module 7).
    Catches OCR misreads or impossible macronutrient combinations.
    """
    warnings: list[str] = []
    missing: list[str] = []

    # Check key missing fields
    if n.energy_kcal is None:
        missing.append("energy_kcal")
    if n.protein_g is None:
        missing.append("protein_g")
    if n.carbs_g is None:
        missing.append("carbs_g")
    if n.fat_g is None:
        missing.append("fat_g")

    # Macro sanity calculations
    p = n.protein_g or 0.0
    c = n.carbs_g or 0.0
    f = n.fat_g or 0.0
    sug = n.sugar_g or 0.0
    sf = n.sat_fat_g or 0.0

    # 1. Atwater factor calculation: 4*(protein + carbs) + 9*fat
    if n.energy_kcal and n.energy_kcal > 20:
        est = (4.0 * (p + c)) + (9.0 * f)
        diff_ratio = abs(est - n.energy_kcal) / n.energy_kcal
        if diff_ratio > 0.25:
            warnings.append("energy_mismatch")

    # 2. Sugar cannot exceed total carbohydrates
    if n.sugar_g is not None and n.carbs_g is not None and sug > (c + 0.5):
        warnings.append("sugar_gt_carbs")

    # 3. Saturated fat cannot exceed total fat
    if n.sat_fat_g is not None and n.fat_g is not None and sf > (f + 0.5):
        warnings.append("satfat_gt_fat")

    return ValidationResult(
        ok=(len(warnings) == 0),
        warnings=warnings,
        missing=missing,
    )
