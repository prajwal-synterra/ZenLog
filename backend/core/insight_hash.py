import hashlib
import json
from typing import Any


def input_hash(
    days: list[dict[str, Any]],
    targets: dict[str, Any],
    goal: str,
    prompt_version: str,
) -> str:
    """
    Rounds macro values so tiny edits (e.g. 500 ml -> 600 ml) do not invalidate
    the report, while meaningful changes (e.g. adding 40g protein meal) do.

    Rows: [logical_date, protein/5 * 5, calories/50 * 50, water/250 * 250, workout, sleep_min // 30]
    """
    rows = []
    # Sort deterministically by date
    sorted_days = sorted(
        days,
        key=lambda x: str(x.get("logical_date") or x.get("date") or ""),
    )
    for d in sorted_days:
        date_str = str(d.get("logical_date") or d.get("date") or "")
        protein_g = float(d.get("protein_g") or 0.0)
        calories = float(d.get("calories") or d.get("calories_kcal") or 0.0)
        water_ml = float(d.get("water_ml") or d.get("hydration_ml") or 0.0)
        workout = bool(d.get("workout") or d.get("workout_done") or False)
        sleep_min = int(d.get("sleep_min") or d.get("sleep_minutes") or 0)

        rows.append([
            date_str,
            int(round(protein_g / 5.0) * 5),
            int(round(calories / 50.0) * 50),
            int(round(water_ml / 250.0) * 250),
            workout,
            int(sleep_min // 30),
        ])

    payload = {
        "d": rows,
        "t": {k: targets[k] for k in sorted(targets.keys())},
        "g": str(goal),
        "v": str(prompt_version),
    }
    serialized = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()
