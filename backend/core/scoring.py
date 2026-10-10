import re
from typing import Any
from backend.models.food_scan import NutritionValues, ScoreBreakdown

GOAL_W = {
    "muscle_gain": {"protein": 1.4, "calories": 0.3, "sugar": 1.0},
    "fat_loss":    {"protein": 1.2, "calories": 1.3, "sugar": 1.2},
    "maintenance": {"protein": 1.0, "calories": 0.6, "sugar": 1.0},
    "mindfulness": {"protein": 0.8, "calories": 0.6, "sugar": 1.2},
}

BASE_SCORE = 55.0

FLAG_KEYWORDS = [
    "palm oil", "palmolein", "hydrogenated", "partially hydrogenated",
    "maltodextrin", "high fructose", "glucose syrup", "corn syrup",
    "invert sugar", "aspartame", "acesulfame", "sucralose", "saccharin",
    "ins 150d", "ins 102", "ins 110", "ins 122", "ins 124", "ins 129", "ins 133",
    "ins 621", "monosodium glutamate", "msg",
    "ins 211", "sodium benzoate", "ins 202", "potassium sorbate",
    "bha", "bht", "tbhq", "artificial color", "artificial flavour"
]


def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


def detect_flags(ingredients: list[str]) -> list[str]:
    """Identifies ultra-processed and controversial ingredient flags."""
    text = " ".join(ingredients).lower()
    flags = []
    for kw in FLAG_KEYWORDS:
        if kw in text:
            # Clean human-readable label
            label = kw.replace("ins ", "E/INS ").title()
            if "Palm" in label:
                label = "Palm Oil"
            elif "Msg" in label or "Glutamate" in label or kw == "ins 621":
                label = "Monosodium Glutamate (MSG)"
            elif "Hydrogenated" in label:
                label = "Hydrogenated Vegetable Fat"
            flags.append(label)
    return list(dict.fromkeys(flags))


def top_reasons(pts: dict[str, float], n: NutritionValues, flags: list[str]) -> list[str]:
    """Generates the top 3 explanatory reasons based on point magnitude."""
    reasons = []

    # Sort items by absolute point impact
    sorted_pts = sorted(pts.items(), key=lambda kv: abs(kv[1]), reverse=True)

    for key, val in sorted_pts:
        if abs(val) < 1.0:
            continue
        if key == "protein" and val > 5:
            reasons.append(f"High protein density ({n.protein_g}g / 100g)")
        elif key == "sugar" and val < -4:
            reasons.append(f"High sugar content ({n.sugar_g}g / 100g)")
        elif key == "sat_fat" and val < -4:
            reasons.append(f"High saturated fat ({n.sat_fat_g}g / 100g)")
        elif key == "sodium" and val < -3:
            reasons.append(f"High sodium ({n.sodium_mg}mg / 100g)")
        elif key == "fiber" and val > 3:
            reasons.append(f"Good source of dietary fiber ({n.fiber_g}g / 100g)")
        elif key == "additives" and val < -2 and flags:
            reasons.append(f"Contains additives: {', '.join(flags[:2])}")
        elif key == "empty_calories" and val < -5:
            reasons.append("Very low protein & fiber with high sugars")
        elif key == "energy" and val < -3:
            reasons.append(f"Calorie-dense without offsetting protein ({n.energy_kcal} kcal / 100g)")
        elif key == "trans_fat" and val < -5:
            reasons.append("Contains trans fat (>0.2g / 100g)")

        if len(reasons) >= 3:
            break

    if not reasons:
        reasons.append("Balanced nutrient profile")

    return reasons[:3]


def score_product(
    n: NutritionValues,
    ingredients: list[str],
    goal: str = "muscle_gain",
) -> ScoreBreakdown:
    """
    Goal-aware 0-100 product rating heuristic per 100g.
    """
    w = GOAL_W.get(goal, GOAL_W["maintenance"])
    kcal = max(float(n.energy_kcal or 1.0), 1.0)
    prot = float(n.protein_g or 0.0)
    prot_per_100kcal = (prot / kcal) * 100.0

    flags = detect_flags(ingredients)

    pts: dict[str, float] = {
        "protein": clamp(prot_per_100kcal * 4.0, 0.0, 25.0) * w["protein"],
        "fiber": clamp(float(n.fiber_g or 0.0) * 2.0, 0.0, 10.0),
        "sugar": -clamp((float(n.sugar_g or 0.0) - 5.0) * 1.25, 0.0, 25.0) * w["sugar"],
        "sat_fat": -clamp((float(n.sat_fat_g or 0.0) - 1.5) * 2.0, 0.0, 15.0),
        "sodium": -clamp((float(n.sodium_mg or 0.0) - 120.0) * 0.03125, 0.0, 15.0),
        "trans_fat": -10.0 if float(n.trans_fat_g or 0.0) > 0.2 else 0.0,
        "additives": -min(9.0, 1.5 * len(flags)),
    }

    if prot_per_100kcal < 8.0:
        pts["energy"] = -clamp((kcal - 150.0) / 20.0, 0.0, 10.0) * w["calories"]

    if prot < 2.0 and float(n.fiber_g or 0.0) < 1.0 and float(n.sugar_g or 0.0) > 8.0:
        pts["empty_calories"] = -15.0

    total_val = BASE_SCORE + sum(pts.values())
    final_score = round(clamp(total_val, 0.0, 100.0))

    if final_score >= 70:
        grade = "Great"
    elif final_score >= 50:
        grade = "Okay"
    elif final_score >= 30:
        grade = "Occasional"
    else:
        grade = "Skip"

    reasons = top_reasons(pts, n, flags)

    return ScoreBreakdown(
        value=int(final_score),
        grade=grade,
        reasons=reasons,
        breakdown={k: round(v, 2) for k, v in pts.items()},
    )
