"""
Progress & scoring engine for ZenLog v2.

All numbers are computed deterministically by backend code.
Gemini only writes narrative text on top of these numbers.
"""
from datetime import datetime, date as date_type, timedelta
from typing import Any

from backend.models.log import IST


# ---------- Pace curve ----------
# (time_str, expected_fraction_of_daily_target)
PROTEIN_PACE_POINTS = [
    ("08:00", 0.0),
    ("10:30", 0.25),
    ("14:30", 0.50),
    ("19:30", 0.80),
    ("22:00", 1.0),
]


def _time_to_minutes(t: str) -> int:
    h, m = map(int, t.split(":"))
    return h * 60 + m


def _expected_fraction(now_minutes: int, pace_points: list[tuple[str, float]]) -> float:
    """Linear interpolation between pace points."""
    pts = [(_time_to_minutes(t), f) for t, f in pace_points]
    if now_minutes <= pts[0][0]:
        return pts[0][1]
    if now_minutes >= pts[-1][0]:
        return pts[-1][1]
    for i in range(len(pts) - 1):
        t0, f0 = pts[i]
        t1, f1 = pts[i + 1]
        if t0 <= now_minutes <= t1:
            frac = (now_minutes - t0) / (t1 - t0)
            return f0 + frac * (f1 - f0)
    return 1.0


def _meals_left_estimate(now_minutes: int) -> int:
    if now_minutes < _time_to_minutes("10:30"):
        return 3
    if now_minutes < _time_to_minutes("14:30"):
        return 2
    if now_minutes < _time_to_minutes("19:30"):
        return 1
    return 1


def _status_min(actual: float, target: float, expected: float) -> str:
    pct = actual / target if target else 0.0
    if pct >= 1.0:
        return "met"
    if pct >= expected * 0.9:
        return "on_track"
    if pct >= expected * 0.6:
        return "behind"
    return "far_behind"


def _status_max(actual: float, target: float) -> str:
    if actual <= target:
        return "on_track"
    over_frac = (actual - target) / (0.3 * target) if target else 1.0
    if over_frac >= 1.0:
        return "far_behind"
    return "behind"


def _status_range(actual: float, lo: float, hi: float) -> str:
    if lo <= actual <= hi:
        return "met"
    if actual < lo:
        ratio = actual / lo if lo else 0.0
        if ratio >= 0.9:
            return "on_track"
        if ratio >= 0.6:
            return "behind"
        return "far_behind"
    # above hi
    over_frac = (actual - hi) / (0.3 * hi) if hi else 1.0
    if over_frac >= 1.0:
        return "far_behind"
    return "over"


def compute_progress(
    totals: dict,
    targets: dict,
    mode: str,  # "today" | "past"
    now_ist: datetime | None = None,
    week_done: int = 0,
) -> dict:
    """
    Compute per-metric progress and alerts.
    For mode=today uses pace-aware status; for past uses plain thresholds.
    """
    protein_actual = totals.get("protein_g") or 0.0
    water_actual = totals.get("hydration_ml") or 0.0
    cal_actual = totals.get("calories_kcal") or 0.0
    workout_done = bool(totals.get("workout_done"))

    protein_target = targets.get("protein_g") or 0.0
    water_target = targets.get("water_ml") or 3000.0
    cal_target = targets.get("calories_kcal")
    workout_week_target = targets.get("weekly_workout_target") or 3
    goal = targets.get("goal", "muscle_gain")

    now_minutes = 0
    expected_protein_frac = 1.0
    expected_water_frac = 1.0

    if mode == "today" and now_ist:
        now_minutes = now_ist.hour * 60 + now_ist.minute
        expected_protein_frac = _expected_fraction(now_minutes, PROTEIN_PACE_POINTS)
        # Hydration: linear 6 AM → 10 PM
        eating_start = 6 * 60
        eating_end = 22 * 60
        if now_minutes <= eating_start:
            expected_water_frac = 0.0
        elif now_minutes >= eating_end:
            expected_water_frac = 1.0
        else:
            expected_water_frac = (now_minutes - eating_start) / (eating_end - eating_start)

    def _protein_status():
        if mode == "today":
            return _status_min(protein_actual, protein_target, expected_protein_frac) if protein_target else "on_track"
        else:
            pct = protein_actual / protein_target if protein_target else 0.0
            if pct >= 1.0: return "met"
            if pct >= 0.80: return "on_track"
            if pct >= 0.60: return "behind"
            return "far_behind"

    def _water_status():
        if mode == "today":
            return _status_min(water_actual, water_target, expected_water_frac) if water_target else "on_track"
        else:
            pct = water_actual / water_target if water_target else 0.0
            if pct >= 1.0: return "met"
            if pct >= 0.80: return "on_track"
            if pct >= 0.60: return "behind"
            return "far_behind"

    def _calories_status():
        if not cal_target:
            return "on_track"
        if goal == "fat_loss":
            return _status_max(cal_actual, cal_target)
        elif goal in ("muscle_gain", "maintenance"):
            lo = cal_target * (0.95 if goal == "muscle_gain" else 0.90)
            hi = cal_target * (1.15 if goal == "muscle_gain" else 1.10)
            if mode == "today":
                # During the day, going over is the risk; under is fine early
                if cal_actual > hi:
                    return _status_range(cal_actual, lo, hi)
                return "on_track"
            return _status_range(cal_actual, lo, hi)
        return "on_track"

    protein_status = _protein_status()
    water_status = _water_status()
    cal_status = _calories_status()

    # Build alerts
    alerts = []

    if protein_target and protein_status in ("behind", "far_behind"):
        remaining = max(protein_target - protein_actual, 0)
        meals_left = _meals_left_estimate(now_minutes) if mode == "today" else 1
        per_meal = round(remaining / max(meals_left, 1))
        level = "error" if protein_status == "far_behind" else "warn"
        alerts.append({
            "level": level,
            "metric": "protein",
            "text": f"{remaining:.0f}g protein left. ~{per_meal}g per remaining meal." if mode == "today"
                    else f"{remaining:.0f}g protein short.",
        })

    if water_status in ("behind", "far_behind"):
        remaining_ml = max(water_target - water_actual, 0)
        level = "error" if water_status == "far_behind" else "warn"
        alerts.append({
            "level": level,
            "metric": "water",
            "text": f"Only {water_actual:.0f}ml water. Drink {min(500, remaining_ml):.0f}ml now." if water_actual < 500
                    else f"{remaining_ml:.0f}ml water remaining.",
        })

    progress = {
        "protein": {
            "actual": round(protein_actual, 1),
            "target": protein_target,
            "pct": round(protein_actual / protein_target * 100, 1) if protein_target else 0,
            "remaining": round(max(protein_target - protein_actual, 0), 1),
            "direction": "min",
            "status": protein_status,
            "expected_pct_now": round(expected_protein_frac * 100, 1) if mode == "today" else None,
        },
        "water": {
            "actual": round(water_actual),
            "target": round(water_target),
            "pct": round(water_actual / water_target * 100, 1) if water_target else 0,
            "remaining": round(max(water_target - water_actual, 0)),
            "direction": "min",
            "status": water_status,
            "expected_pct_now": round(expected_water_frac * 100, 1) if mode == "today" else None,
        },
        "calories": {
            "actual": round(cal_actual),
            "target": round(cal_target) if cal_target else None,
            "pct": round(cal_actual / cal_target * 100, 1) if cal_target else None,
            "direction": "max" if goal == "fat_loss" else "range",
            "status": cal_status,
        },
        "workout": {
            "done": workout_done,
            "week_done": week_done,
            "week_target": workout_week_target,
            "status": "met" if workout_done else "pending",
        },
        "alerts": alerts,
    }
    return progress


# ---------- Scoring ----------
GOAL_WEIGHTS = {
    "muscle_gain":  {"protein": 30, "calories": 20, "hydration": 15, "workout": 15, "food_quality": 10, "habits": 10},
    "maintenance":  {"protein": 30, "calories": 20, "hydration": 15, "workout": 15, "food_quality": 10, "habits": 10},
    "fat_loss":     {"protein": 25, "calories": 30, "hydration": 15, "workout": 15, "food_quality": 10, "habits": 5},
    "mindfulness":  {"protein": 10, "calories": 5,  "hydration": 15, "workout": 10, "food_quality": 10, "habits": 50},
}

STATUS_TO_SUBSCORE = {
    "met": 1.0, "on_track": 0.85, "behind": 0.55, "far_behind": 0.2,
    "over": 0.2, "pending": 0.0, "impossible": 0.0,
}


def compute_day_score(totals: dict, targets: dict, entries: list[dict]) -> tuple[int, str]:
    """
    Compute 0-100 day score and rating string.
    Returns (score, rating) where rating is 'good'|'ok'|'poor'|'insufficient_data'.
    """
    if len(entries) < 2:
        return 0, "insufficient_data"

    progress = compute_progress(totals, targets, mode="past")
    goal = targets.get("goal", "muscle_gain")
    weights = GOAL_WEIGHTS.get(goal, GOAL_WEIGHTS["muscle_gain"])

    scores = {}

    # Protein
    scores["protein"] = STATUS_TO_SUBSCORE.get(progress["protein"]["status"], 0.0)

    # Hydration
    scores["hydration"] = STATUS_TO_SUBSCORE.get(progress["water"]["status"], 0.0)

    # Calories (if target set)
    if targets.get("calories_kcal"):
        scores["calories"] = STATUS_TO_SUBSCORE.get(progress["calories"]["status"], 0.0)

    # Workout
    if totals.get("workout_done"):
        scores["workout"] = 1.0
    else:
        scores["workout"] = 0.0

    # Food quality from goal_alignment ratings
    quality_scores = []
    for entry in entries:
        extracted = entry.get("extracted") or {}
        ga = extracted.get("goal_alignment") or {}
        rating = ga.get("rating", "not_applicable")
        if rating == "good":
            quality_scores.append(1.0)
        elif rating == "neutral":
            quality_scores.append(0.6)
        elif rating == "poor":
            quality_scores.append(0.0)
    if quality_scores:
        scores["food_quality"] = sum(quality_scores) / len(quality_scores)

    # Habits
    habit_obs = []
    for entry in entries:
        extracted = entry.get("extracted") or {}
        for h in (extracted.get("habits") or []):
            if h.get("completed") is not None:
                habit_obs.append(1.0 if h["completed"] else 0.0)
    if habit_obs:
        scores["habits"] = sum(habit_obs) / len(habit_obs)

    # Weighted average (skip metrics with no score)
    total_weight = 0
    weighted_sum = 0.0
    for metric, weight in weights.items():
        if metric in scores:
            weighted_sum += weight * scores[metric]
            total_weight += weight

    score = round(weighted_sum / total_weight * 100) if total_weight else 0
    if score >= 80:
        rating = "good"
    elif score >= 60:
        rating = "ok"
    else:
        rating = "poor"

    return score, rating


# ---------- Totals from entries ----------
def compute_day_totals(entries: list[dict]) -> dict:
    """Sum extraction values across all done entries."""
    protein_g = 0.0
    calories_kcal = 0.0
    hydration_ml = 0
    workout_done = False
    workout_mins = 0

    for entry in entries:
        if entry.get("extraction_status") != "done":
            continue
        extracted = entry.get("extracted") or {}
        overrides = entry.get("overrides") or {}

        # Protein — use override if present
        p = overrides.get("protein_g", (extracted.get("nutrition") or {}).get("protein_g"))
        if p is not None:
            protein_g += p

        # Calories — use override if present
        c = overrides.get("calories_kcal", (extracted.get("nutrition") or {}).get("calories_kcal"))
        if c is not None:
            calories_kcal += c

        # Hydration — use override if present
        h = overrides.get("hydration_ml", extracted.get("hydration_ml"))
        if h is not None:
            hydration_ml += h

        # Workout
        w = extracted.get("workout")
        if w:
            workout_done = True
            workout_mins += w.get("duration_mins") or 0

    return {
        "protein_g": round(protein_g, 1),
        "calories_kcal": round(calories_kcal, 1),
        "hydration_ml": hydration_ml,
        "workout_done": workout_done,
        "workout_mins": workout_mins,
    }
