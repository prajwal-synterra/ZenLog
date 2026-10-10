import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

_root = str(Path(__file__).resolve().parent.parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

from dotenv import load_dotenv
from fastapi.testclient import TestClient

from backend.main import app

load_dotenv(Path(_root) / "backend" / ".env")


def test_m4_quick_actions():
    with TestClient(app) as client:
        # 1. Login test user with PIN
        login_res = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "4321",
        })
        assert login_res.status_code == 200, f"Login failed: {login_res.text}"
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 2. Test Quick Water Structured Log
        water_cid = f"water-cid-{uuid.uuid4()}"
        water_res = client.post("/api/logs/structured", headers=headers, json={
            "text": "250 ml water",
            "extracted": {"hydration_ml": 250, "water_ml": 250},
            "source": "water_quick",
            "client_id": water_cid,
        })
        assert water_res.status_code == 201, f"Water log failed: {water_res.text}"
        water_data = water_res.json()
        assert water_data["source"] == "water_quick"
        assert water_data["extraction_status"] == "done"
        assert water_data["extracted"]["hydration_ml"] == 250

        # 3. Create Manual Saved Meal
        shake_res = client.post("/api/saved-meals", headers=headers, json={
            "name": "Whey Protein Shake",
            "raw_text": "1 scoop whey in 250ml milk",
            "extracted": {
                "protein_g": 30.0,
                "calories": 180,
                "carbs_g": 12.0,
                "fat_g": 3.0,
            },
            "pinned": False,
        })
        assert shake_res.status_code == 201, f"Create saved meal failed: {shake_res.text}"
        shake = shake_res.json()
        shake_id = shake["id"]
        assert shake["name"] == "Whey Protein Shake"
        assert shake["use_count"] == 0

        # 4. Create Saved Meal From an Existing Log
        egg_log_res = client.post("/api/logs/structured", headers=headers, json={
            "text": "3 boiled eggs",
            "extracted": {"protein_g": 18.0, "calories": 210},
            "source": "structured",
            "client_id": f"egg-cid-{uuid.uuid4()}",
        })
        assert egg_log_res.status_code == 201
        egg_log_id = egg_log_res.json()["id"]

        egg_meal_res = client.post("/api/saved-meals", headers=headers, json={
            "log_id": egg_log_id,
            "name": "Standard 3 Eggs",
        })
        assert egg_meal_res.status_code == 201
        egg_meal = egg_meal_res.json()
        egg_meal_id = egg_meal["id"]
        assert egg_meal["name"] == "Standard 3 Eggs"
        assert egg_meal["extracted"]["protein_g"] == 18.0

        # 5. List Saved Meals & Edit/Pin
        list_res = client.get("/api/saved-meals", headers=headers)
        assert list_res.status_code == 200
        meals = list_res.json()
        assert len(meals) >= 2

        # Pin the shake
        update_res = client.put(f"/api/saved-meals/{shake_id}", headers=headers, json={
            "pinned": True,
            "name": "Morning Whey Shake",
        })
        assert update_res.status_code == 200
        assert update_res.json()["pinned"] is True
        assert update_res.json()["name"] == "Morning Whey Shake"

        # List again: pinned should be first
        list_res2 = client.get("/api/saved-meals", headers=headers)
        assert list_res2.status_code == 200
        meals2 = list_res2.json()
        assert meals2[0]["id"] == shake_id

        # 6. Test Logging a Saved Meal with 1.5x Portion
        log_fav_res = client.post(f"/api/saved-meals/{shake_id}/log", headers=headers, json={
            "portion": 1.5,
            "client_id": f"fav-cid-{uuid.uuid4()}",
        })
        assert log_fav_res.status_code == 201, f"Log fav failed: {log_fav_res.text}"
        fav_log_data = log_fav_res.json()
        assert fav_log_data["source"] == "saved_meal"
        # 30.0 * 1.5 = 45.0 protein, 180 * 1.5 = 270 calories
        assert fav_log_data["extracted"]["protein_g"] == 45.0
        assert fav_log_data["extracted"]["calories"] == 270
        assert fav_log_data["text"] == "Morning Whey Shake (1.5x)"

        # Check use_count incremented
        shake_check = client.get("/api/saved-meals", headers=headers).json()
        shake_doc = next(m for m in shake_check if m["id"] == shake_id)
        assert shake_doc["use_count"] == 1
        assert shake_doc["last_used_at"] is not None

        # 7. Test Suggestions: Log "Greek Yogurt & Berries" 3 times
        for i in range(3):
            client.post("/api/logs/structured", headers=headers, json={
                "text": "Greek Yogurt & Berries",
                "extracted": {"protein_g": 20.0, "calories": 150},
                "source": "structured",
                "client_id": f"yogurt-cid-{i}-{uuid.uuid4()}",
            })

        sug_res = client.get("/api/saved-meals/suggestions", headers=headers)
        assert sug_res.status_code == 200
        suggestions = sug_res.json()
        assert any("greek yogurt" in s["raw_text"].lower() and s["count"] >= 3 for s in suggestions), f"Suggestions: {suggestions}"

        # 8. Clean up
        client.delete(f"/api/saved-meals/{shake_id}", headers=headers)
        client.delete(f"/api/saved-meals/{egg_meal_id}", headers=headers)
        client.delete(f"/api/logs/{water_data['id']}", headers=headers)
        client.delete(f"/api/logs/{fav_log_data['id']}", headers=headers)
        client.delete(f"/api/logs/{egg_log_id}", headers=headers)

        print("ALL M4 BACKEND QUICK ACTIONS & SAVED MEALS TESTS PASSED SUCCESSFULLY!")


if __name__ == "__main__":
    test_m4_quick_actions()
