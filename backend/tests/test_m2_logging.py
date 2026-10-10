import sys
from pathlib import Path
_root = str(Path(__file__).resolve().parent.parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

import os
import uuid
from datetime import datetime, timedelta
from dotenv import load_dotenv
from fastapi.testclient import TestClient

from backend.core.timeutil import IST, logical_date
from backend.main import app

load_dotenv(Path(_root) / "backend" / ".env")


def test_m2_logging_endpoints():
    with TestClient(app) as client:
        # 1. Login test user
        login_res = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "4321",
            "phone_number": "9000000001",
        })
        assert login_res.status_code == 200, f"Login failed: {login_res.text}"
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 2. Test idempotency with client_id
        cid = f"test-cid-{uuid.uuid4()}"
        log1 = client.post("/api/logs", headers=headers, json={
            "text": "3 eggs and black coffee",
            "client_id": cid,
        })
        assert log1.status_code == 201, f"Create failed: {log1.text}"
        log1_id = log1.json()["id"]

        # Replaying same client_id should return 200 OK with same log
        log2 = client.post("/api/logs", headers=headers, json={
            "text": "3 eggs and black coffee",
            "client_id": cid,
        })
        assert log2.status_code == 200, f"Idempotency replay failed: {log2.text}"
        assert log2.json()["id"] == log1_id

        # 3. Test backfill into past date with 4 AM rule
        # Wednesday 01:30 AM IST -> should resolve to Tuesday
        t_wed_early = datetime(2026, 10, 7, 1, 30, tzinfo=IST)
        log_past = client.post("/api/logs", headers=headers, json={
            "text": "Late night protein shake 30g",
            "logged_at": t_wed_early.isoformat(),
            "client_id": f"cid-{uuid.uuid4()}",
        })
        assert log_past.status_code == 201, f"Past log failed: {log_past.text}"
        past_data = log_past.json()
        assert past_data["date"] == "2026-10-06", f"Expected 2026-10-06 under 4 AM rule, got {past_data['date']}"

        # 4. Test structured log creation (NO Gemini call needed)
        structured_cid = f"cid-{uuid.uuid4()}"
        log_struct = client.post("/api/logs/structured", headers=headers, json={
            "text": "500ml water",
            "extracted": {"hydration_ml": 500},
            "source": "water_quick",
            "client_id": structured_cid,
        })
        assert log_struct.status_code == 201, f"Structured log failed: {log_struct.text}"
        struct_data = log_struct.json()
        assert struct_data["extraction_status"] == "done"
        assert struct_data["extracted"] == {"hydration_ml": 500}
        assert struct_data["source"] == "water_quick"

        # 5. Test repeat log creation
        repeat_log = client.post(f"/api/logs/{log1_id}/repeat", headers=headers, json={
            "client_id": f"cid-{uuid.uuid4()}",
        })
        assert repeat_log.status_code == 201, f"Repeat log failed: {repeat_log.text}"
        repeat_data = repeat_log.json()
        assert repeat_data["text"] == "3 eggs and black coffee"
        assert repeat_data["source"] == "repeat"

        # 6. Test PUT update log (moving time/day without re-extracting)
        t_new = datetime(2026, 10, 6, 14, 0, tzinfo=IST)
        updated = client.put(f"/api/logs/{log1_id}", headers=headers, json={
            "logged_at": t_new.isoformat(),
        })
        assert updated.status_code == 200, f"Update log failed: {updated.text}"
        assert updated.json()["date"] == "2026-10-06"

        # Cleanup test entries
        client.delete(f"/api/logs/{log1_id}", headers=headers)
        client.delete(f"/api/logs/{past_data['id']}", headers=headers)
        client.delete(f"/api/logs/{struct_data['id']}", headers=headers)
        client.delete(f"/api/logs/{repeat_data['id']}", headers=headers)

        print("ALL M2 BACKEND LOGGING TESTS PASSED SUCCESSFULLY!")


if __name__ == "__main__":
    test_m2_logging_endpoints()
