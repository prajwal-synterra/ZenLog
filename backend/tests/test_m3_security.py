import os
import sys
from pathlib import Path

_root = str(Path(__file__).resolve().parent.parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

from datetime import datetime, timezone
from dotenv import load_dotenv
from fastapi.testclient import TestClient

from backend.core.security import hash_pin, verify_pin
from backend.main import app

load_dotenv(Path(_root) / "backend" / ".env")


def test_m3_security_and_export():
    with TestClient(app) as client:
        # 1. Test PIN hashing and verification
        test_pin = "4321"
        pin_hash = hash_pin(test_pin)
        assert verify_pin(test_pin, pin_hash) is True
        assert verify_pin("9999", pin_hash) is False
        assert verify_pin("", pin_hash) is False

        # Set PIN on testuser1
        db = app.state.database
        db["users"].update_one(
            {"username": "testuser1"},
            {"$set": {"pin_hash": pin_hash}},
        )
        # Clear any prior failed attempts
        db["login_attempts"].delete_many({"username": "testuser1"})

        # 2. Test login with wrong PIN -> 401
        res_wrong = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "0000",
        })
        assert res_wrong.status_code == 401
        assert "Username or PIN incorrect." in res_wrong.text

        # 3. Test login with correct PIN -> 200
        res_ok = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "4321",
        })
        assert res_ok.status_code == 200, f"Login failed: {res_ok.text}"
        data = res_ok.json()
        token = data["access_token"]
        assert token is not None
        headers = {"Authorization": f"Bearer {token}"}

        # 4. Test brute force protection: 5 failures -> 429 on 6th attempt
        db["login_attempts"].delete_many({"username": "testuser1"})
        for i in range(5):
            res_fail = client.post("/api/auth/login", json={
                "username": "testuser1",
                "pin": f"999{i}",
            })
            assert res_fail.status_code == 401

        res_locked = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "4321",  # Even with correct PIN, should be locked out
        })
        assert res_locked.status_code == 429, f"Expected 429 lockout, got {res_locked.status_code}"
        assert "Too many failed login attempts" in res_locked.text

        # Clear lockout to test export
        db["login_attempts"].delete_many({"username": "testuser1"})

        # 5. Test Export JSON
        export_json = client.get("/api/export?format=json", headers=headers)
        assert export_json.status_code == 200
        json_data = export_json.json()
        assert json_data["version"] == "1.0"
        assert json_data["user"]["username"] == "testuser1"
        assert "logs" in json_data
        assert "days" in json_data
        # Ensure pin_hash was not leaked in user profile export
        assert "pin_hash" not in json_data["user"]

        # 6. Test Export CSV
        export_csv = client.get("/api/export?format=csv", headers=headers)
        assert export_csv.status_code == 200
        assert export_csv.headers["content-type"].startswith("text/csv")
        csv_text = export_csv.text
        assert "id,date,logged_at,text,protein_g,calories_kcal,hydration_ml" in csv_text

        print("ALL M3 SECURITY & EXPORT TESTS PASSED SUCCESSFULLY!")


if __name__ == "__main__":
    test_m3_security_and_export()
