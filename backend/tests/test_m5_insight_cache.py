import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

_root = str(Path(__file__).resolve().parent.parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

from dotenv import load_dotenv
from fastapi.testclient import TestClient

from backend.core.insight_hash import input_hash
from backend.main import app
from backend.models.extraction import InsightReport

load_dotenv(Path(_root) / "backend" / ".env")


def test_hash_rounding_behavior():
    """
    Module 5 Hash Rule:
    - Water: round(water / 250) * 250 -> 500 ml vs 600 ml both round to 500 ml
    - Protein: round(protein / 5) * 5 -> adding 40g shifts hash
    """
    day1 = {
        "logical_date": "2026-10-01",
        "protein_g": 120.0,
        "calories": 2000.0,
        "water_ml": 500.0,
        "workout": True,
        "sleep_min": 450,
    }
    targets = {"protein_g": 130, "calories_kcal": 2100, "water_ml": 3000}
    goal = "muscle_gain"
    v = "v1"

    hash_500 = input_hash([day1], targets, goal, v)

    # Change water to 600 ml (rounds to 500 ml) -> hash must be identical
    day1_water600 = dict(day1, water_ml=600.0)
    hash_600 = input_hash([day1_water600], targets, goal, v)
    assert hash_500 == hash_600, "Minor water change (500ml -> 600ml) should not change hash"

    # Add 40g protein (120g -> 160g) -> hash must differ
    day1_protein = dict(day1, protein_g=160.0)
    hash_protein = input_hash([day1_protein], targets, goal, v)
    assert hash_500 != hash_protein, "Meaningful protein change (+40g) must invalidate hash"


def test_m5_insight_cache_and_verdict():
    with TestClient(app) as client:
        # 1. Login
        login_res = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "4321",
        })
        assert login_res.status_code == 200, f"Login failed: {login_res.text}"
        token = login_res.json()["access_token"]
        user_id = login_res.json()["user"]["user_id"]
        headers = {"Authorization": f"Bearer {token}"}

        # Clear any prior test entries for 2026-10-05 through 2026-10-10
        db = app.state.database
        db["daily_logs"].delete_many({"user_id": user_id, "date": {"$gte": "2026-10-05", "$lte": "2026-10-10"}})
        db["insight_cache"].delete_many({"user_id": user_id})
        db["reports"].delete_many({"user_id": user_id})

        # 2. GET cached insight before generating -> should be "none"
        get_res = client.get("/api/insights/weekly?date=2026-10-07", headers=headers)
        assert get_res.status_code == 200
        get_data = get_res.json()
        assert get_data["status"] == "none"

        # 3. Create at least 3 days of logs for testing
        test_days = ["2026-10-05", "2026-10-06", "2026-10-07"]
        for d in test_days:
            client.post("/api/logs/structured", headers=headers, json={
                "text": f"Healthy lunch on {d}",
                "extracted": {
                    "protein_g": 35.0,
                    "calories": 500,
                    "hydration_ml": 500,
                },
                "source": "text",
                "logged_at": f"{d}T13:00:00+05:30",
                "client_id": str(uuid.uuid4()),
            })

        mock_report = InsightReport(
            summary="Solid consistency across tracked days.",
            highlights=["Met protein target twice", "Maintained regular hydration"],
            areas_to_improve=["Sleep earlier"],
            coaching_notes="Keep this rhythm going.",
        )

        with patch("backend.routes.insights.generate_period_insight") as mock_gen:
            mock_gen.return_value = (mock_report, "gemini-2.5-flash-mock")

            # 4. First generation: calls Gemini
            gen_res = client.post(
                "/api/insights/weekly/generate",
                headers=headers,
                json={"force": True, "anchor": "2026-10-07"},
            )
            assert gen_res.status_code == 200, f"Generate failed: {gen_res.text}"
            gen_data = gen_res.json()
            assert gen_data["status"] == "fresh"
            assert gen_data["report"]["summary"] == "Solid consistency across tracked days."
            assert mock_gen.call_count == 1

            # 5. Second generation call with matching data and force=False -> reuses cache with 0 Gemini calls
            gen2_res = client.post(
                "/api/insights/weekly/generate",
                headers=headers,
                json={"force": False, "anchor": "2026-10-07"},
            )
            assert gen2_res.status_code == 200
            gen2_data = gen2_res.json()
            assert gen2_data["status"] == "fresh"
            assert mock_gen.call_count == 1  # No additional Gemini call!

        # 6. GET cached insight -> returns status "fresh" without calling Gemini
        get_fresh = client.get("/api/insights/weekly?date=2026-10-07", headers=headers)
        assert get_fresh.status_code == 200
        assert get_fresh.json()["status"] == "fresh"

        # 7. Add water entry with minor change (500 ml -> 600 ml total)
        # Adding 100ml water to day 2026-10-05: 500 + 100 = 600ml
        # In input_hash: round(600 / 250) * 250 = 500 -> HASH DOES NOT CHANGE
        client.post("/api/logs/structured", headers=headers, json={
            "text": "100 ml water",
            "extracted": {"hydration_ml": 100, "water_ml": 100},
            "source": "water_quick",
            "logged_at": "2026-10-05T15:00:00+05:30",
            "client_id": str(uuid.uuid4()),
        })
        get_after_water = client.get("/api/insights/weekly?date=2026-10-07", headers=headers)
        assert get_after_water.status_code == 200
        assert get_after_water.json()["status"] == "fresh", "Minor water addition should leave weekly insight fresh"

        # 8. Add a meaningful meal (+40g protein) -> hash changes, status becomes "stale"
        client.post("/api/logs/structured", headers=headers, json={
            "text": "Chicken breast snack 40g protein",
            "extracted": {"protein_g": 40.0, "calories": 250},
            "source": "text",
            "logged_at": "2026-10-06T17:00:00+05:30",
            "client_id": str(uuid.uuid4()),
        })
        get_after_protein = client.get("/api/insights/weekly?date=2026-10-07", headers=headers)
        assert get_after_protein.status_code == 200
        assert get_after_protein.json()["status"] == "stale", "Adding 40g protein meal must mark report as stale"

        # 9. Verify 10-minute cooldown on generate when data is stale
        with patch("backend.routes.insights.generate_period_insight") as mock_gen_fail:
            cooldown_res = client.post(
                "/api/insights/weekly/generate",
                headers=headers,
                json={"force": False, "anchor": "2026-10-07"},
            )
            assert cooldown_res.status_code == 200
            cd_data = cooldown_res.json()
            assert cd_data["status"] == "stale"
            assert cd_data["warning"] is not None
            assert "cooldown" in cd_data["warning"].lower()
            assert mock_gen_fail.call_count == 0  # Blocked by cooldown!

        # 10. Verify fallback to stale report if Gemini errors with force=True
        with patch("backend.routes.insights.generate_period_insight") as mock_gen_err:
            mock_gen_err.side_effect = RuntimeError("Gemini 503 Quota Exceeded")
            fallback_res = client.post(
                "/api/insights/weekly/generate",
                headers=headers,
                json={"force": True, "anchor": "2026-10-07"},
            )
            assert fallback_res.status_code == 200
            fb_data = fallback_res.json()
            assert fb_data["status"] == "stale"
            assert fb_data["report"] is not None, "Fallback must preserve last report"
            assert fb_data["warning"] is not None

        # 11. Day Verdict Endpoints
        day_get = client.get("/api/days/2026-10-07/verdict", headers=headers)
        assert day_get.status_code == 200
        d_data = day_get.json()
        assert "status" in d_data
        assert d_data["day"] == "2026-10-07"

        # Cleanup test data
        db["daily_logs"].delete_many({"user_id": user_id, "date": {"$gte": "2026-10-05", "$lte": "2026-10-10"}})
        db["insight_cache"].delete_many({"user_id": user_id})
        db["reports"].delete_many({"user_id": user_id})

        print("ALL M5 HASH-BASED INSIGHT CACHE & VERDICT TESTS PASSED!")


if __name__ == "__main__":
    test_hash_rounding_behavior()
    test_m5_insight_cache_and_verdict()
