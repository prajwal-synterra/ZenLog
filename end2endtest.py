import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from dotenv import load_dotenv
from fastapi.testclient import TestClient
from pymongo import MongoClient
from pymongo.server_api import ServerApi
from pydantic import BaseModel

from backend.ai.gemini_client import generate_structured
from backend.main import app
from backend.models.extraction import (
    DailyExtraction,
    ExtractedFood,
    ExtractedMeal,
    InsightReport,
    LearningActivity,
    NutritionExtraction,
    WorkoutExtraction,
)
from backend.models.log import IST


ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / "backend" / ".env")
TEST_USER = {
    "user_id": "zen_test_0001",
    "username": "testuser1",
    "name": "ZenLog Test User",
    "phone_number": "9000000001",
    "goal": "muscle_gain",
    "body_weight_kg": 70.0,
    "daily_protein_target_g": 126.0,
}


def fixture_day_extraction(logs: list[dict]) -> tuple[DailyExtraction, str]:
    return DailyExtraction(
        nutrition=NutritionExtraction(
            meals=[
                ExtractedMeal(
                    meal="breakfast",
                    items=[
                        ExtractedFood(
                            food="egg",
                            quantity="3",
                            protein_g=18,
                            calories_kcal=210,
                            protein_source="estimated",
                            confidence="high",
                        )
                    ],
                )
            ],
            water_intake_ml=[750],
        ),
        workouts=[WorkoutExtraction(type="strength_training", duration_mins=45)],
        learning=[LearningActivity(activity="reading", book="Atomic Habits", pages=10)],
    ), "test-fixture"


def fixture_period_insight(period: str, summary: dict) -> tuple[InsightReport, str]:
    return InsightReport(
        summary=f"Test {period} insight based on persisted aggregate data.",
        highlights=["The test scenario produced a completed journal day."],
        areas_to_improve=[],
        coaching_notes="This is a schema fixture used only when Gemini is unavailable.",
    ), "test-fixture"


def verify_model_fallback() -> bool:
    class FallbackProbe(BaseModel):
        ok: bool

    calls = []

    class FakeChat:
        def __init__(self, model):
            self.model = model

        def send_message(self, prompt):
            if self.model == "primary-test-model":
                raise RuntimeError("simulated primary failure")
            return SimpleNamespace(parsed={"ok": True}, text='{"ok": true}')

    class FakeChats:
        def create(self, model, **kwargs):
            calls.append(model)
            return FakeChat(model)

    fake_client = SimpleNamespace(chats=FakeChats())
    with (
        patch.dict(
            os.environ,
            {
                "GEMINI_API_KEY": "test-key",
                "GEMINI_MODEL": "primary-test-model",
                "GEMINI_FALLBACK_MODELS": "fallback-test-model",
            },
        ),
        patch("backend.ai.gemini_client.genai.Client", return_value=fake_client),
    ):
        result, model_used = generate_structured(FallbackProbe, "test prompt")
    return result.ok and model_used == "fallback-test-model" and calls == [
        "primary-test-model",
        "fallback-test-model",
    ]


def check(results: dict, name: str, passed: bool, detail: str = "") -> bool:
    results[name] = {"status": "PASS" if passed else "FAIL"}
    if detail:
        results[name]["detail"] = detail
    return passed


def prepare_test_user() -> None:
    uri = os.getenv("MONGODB_URI") or os.getenv("MONGO_URI")
    if not uri:
        raise RuntimeError("Set MONGODB_URI or MONGO_URI in backend/.env.")
    client = MongoClient(uri, server_api=ServerApi("1"), serverSelectionTimeoutMS=5000)
    try:
        client.admin.command("ping")
        database = client[os.getenv("MONGODB_DATABASE", "zenlog")]
        user_filter = {"user_id": TEST_USER["user_id"]}
        database["daily_logs"].delete_many(user_filter)
        database["daily_records"].delete_many(user_filter)
        database["reports"].delete_many(user_filter)
        database["sessions"].delete_many(user_filter)
        database["users"].update_one(user_filter, {"$set": TEST_USER}, upsert=True)
    finally:
        client.close()


def run_scenario() -> dict:
    results = {}
    use_gemini_fixtures = os.getenv("ZENLOG_E2E_USE_GEMINI_FIXTURES", "").lower() in {
        "1",
        "true",
        "yes",
    }
    check(results, "Gemini primary-to-fallback selection", verify_model_fallback())
    prepare_test_user()

    with TestClient(app) as client:
        health = client.get("/health")
        check(
            results,
            "MongoDB-backed health check",
            health.status_code == 200 and health.json().get("database") == "connected",
            f"HTTP {health.status_code}",
        )

        unauthorized = client.get("/api/users/me")
        check(results, "Protected route rejects anonymous user", unauthorized.status_code == 401)

        login = client.post(
            "/api/auth/login",
            json={"username": TEST_USER["username"], "phone_number": TEST_USER["phone_number"]},
        )
        if login.status_code != 200:
            check(results, "Test user login", False, f"HTTP {login.status_code}: {login.text}")
            return results
        check(results, "Test user login", True)
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        profile = client.get("/api/users/me", headers=headers)
        check(
            results,
            "Safe current-user profile",
            profile.status_code == 200
            and profile.json().get("user_id") == TEST_USER["user_id"]
            and "phone_number" not in profile.json(),
            f"HTTP {profile.status_code}",
        )
        updated_profile = client.put(
            "/api/users/me",
            headers=headers,
            json={"goal": "muscle_gain", "body_weight_kg": 70, "daily_protein_target_g": 126},
        )
        check(
            results,
            "Update user goals and protein target",
            updated_profile.status_code == 200
            and updated_profile.json().get("daily_protein_target_g") == 126,
            f"HTTP {updated_profile.status_code}",
        )

        now = datetime.now(IST)
        log_date = now.date().isoformat()
        timestamp = now.isoformat(timespec="seconds")
        created_ids = []
        log_inputs = [
            "Breakfast: 3 eggs and a banana.",
            "Completed 45 minutes of strength training, drank 750 ml water, and read 10 pages of Atomic Habits.",
            "Temporary entry for delete-route verification.",
        ]
        for index, text in enumerate(log_inputs):
            log_payload = {"text": text}
            if index:
                log_payload.update({"date": log_date, "timestamp": timestamp})
            response = client.post(
                "/api/logs",
                headers=headers,
                json=log_payload,
            )
            if response.status_code == 201:
                created_ids.append(response.json()["id"])
        check(results, "Create three raw journal entries", len(created_ids) == 3)

        if len(created_ids) == 3:
            edited = client.put(
                f"/api/logs/{created_ids[0]}",
                headers=headers,
                json={"text": "Breakfast: 3 eggs and a banana (corrected)."},
            )
            check(
                results,
                "Edit raw journal entry",
                edited.status_code == 200 and "corrected" in edited.json().get("text", ""),
                f"HTTP {edited.status_code}",
            )
            deleted = client.delete(f"/api/logs/{created_ids[2]}", headers=headers)
            check(results, "Delete raw journal entry", deleted.status_code == 204)

        today_logs = client.get("/api/logs/today", headers=headers)
        remaining_logs = today_logs.json() if today_logs.status_code == 200 else []
        check(
            results,
            "Retrieve only this user's full-day logs",
            today_logs.status_code == 200
            and len(remaining_logs) == 2
            and all(log["user_id"] == TEST_USER["user_id"] for log in remaining_logs)
            and all(log["date"] == log_date for log in remaining_logs),
            f"HTTP {today_logs.status_code}; {len(remaining_logs)} entries",
        )
        ranged_logs = client.get(
            f"/api/logs?start_date={log_date}&end_date={log_date}", headers=headers
        )
        check(
            results,
            "Inclusive date-range log retrieval",
            ranged_logs.status_code == 200 and len(ranged_logs.json()) == 2,
            f"HTTP {ranged_logs.status_code}",
        )

        if use_gemini_fixtures:
            with patch(
                "backend.services.day_service.extract_day",
                side_effect=fixture_day_extraction,
            ):
                completion = client.post(
                    "/api/days/sleep",
                    headers=headers,
                    json={"sleep_time": now.strftime("%H:%M")},
                )
            results["Live Gemini daily generation"] = {
                "status": "SKIPPED",
                "detail": "Fixture mode requested; route and persistence are tested with schema-valid output.",
            }
        else:
            completion = client.post(
                "/api/days/sleep",
                headers=headers,
                json={"sleep_time": now.strftime("%H:%M")},
            )
        completed_record = None
        if completion.status_code == 200:
            completed_record = completion.json()
            check(
                results,
                "Sleep submission and Gemini daily extraction",
                completed_record.get("status") == "COMPLETED"
                and completed_record.get("processing", {}).get("model")
                in {
                    os.getenv("GEMINI_MODEL"),
                    os.getenv("GEMINI_FALLBACK_MODEL"),
                    *(m.strip() for m in (os.getenv("GEMINI_FALLBACK_MODELS") or "").split(",") if m.strip()),
                    "test-fixture",
                },
                f"HTTP {completion.status_code}; "
                + ("schema fixture used" if use_gemini_fixtures else "live model response"),
            )
            check(
                results,
                "Persisted daily record and deterministic totals",
                completed_record.get("schema_version") == "1.0"
                and "daily_totals" in completed_record.get("nutrition", {}),
            )
            duplicate = client.post(
                "/api/days/sleep",
                headers=headers,
                json={"sleep_time": now.strftime("%H:%M")},
            )
            check(results, "Duplicate day submission is rejected", duplicate.status_code == 409)
        else:
            day_state = client.get(f"/api/days/{log_date}", headers=headers)
            day_body = day_state.json() if day_state.status_code == 200 else {}
            failed_record = day_body.get("record") or {}
            error_type = failed_record.get("processing", {}).get("error_type", "unknown")
            recoverable = (
                day_state.status_code == 200
                and day_body.get("status") == "PROCESSING_FAILED"
                and len(day_body.get("logs", [])) == 2
            )
            if completion.status_code == 503 and recoverable:
                results["Sleep submission and Gemini daily extraction"] = {
                    "status": "BLOCKED",
                    "detail": f"Gemini returned 503 ({error_type}); backend preserved logs and marked the day retryable.",
                }
                check(
                    results,
                    "Sleep route handles Gemini outage safely",
                    True,
                    f"PROCESSING_FAILED; {error_type}; both raw logs preserved",
                )
            else:
                check(
                    results,
                    "Sleep submission and Gemini daily extraction",
                    False,
                    f"HTTP {completion.status_code}: {completion.text}",
                )
            check(
                results,
                "Failed AI processing remains recoverable",
                recoverable,
                f"HTTP {day_state.status_code}; error type {error_type}",
            )
            if recoverable:
                with patch(
                    "backend.services.day_service.extract_day",
                    side_effect=fixture_day_extraction,
                ):
                    fixture_retry = client.post(
                        "/api/days/sleep",
                        headers=headers,
                        json={"sleep_time": now.strftime("%H:%M")},
                    )
                completed_record = (
                    fixture_retry.json() if fixture_retry.status_code == 200 else None
                )
                totals = (
                    completed_record.get("nutrition", {}).get("daily_totals", {})
                    if completed_record
                    else {}
                )
                check(
                    results,
                    "Retry persists schema-valid extraction and backend totals",
                    bool(completed_record)
                    and completed_record.get("status") == "COMPLETED"
                    and totals.get("protein_g") == 18
                    and totals.get("target_percentage") == 14.3
                    and totals.get("remaining_protein_g") == 108
                    and totals.get("hydration_ml") == 750,
                    f"HTTP {fixture_retry.status_code}; test fixture used after live Gemini outage",
                )

        if completed_record:
            duplicate = client.post(
                "/api/days/sleep",
                headers=headers,
                json={"sleep_time": now.strftime("%H:%M")},
            )
            check(results, "Duplicate day submission is rejected", duplicate.status_code == 409)

        history = client.get(f"/api/days/{log_date}", headers=headers)
        check(
            results,
            "Daily history returns raw entries and processing state",
            history.status_code == 200 and len(history.json().get("logs", [])) == 2,
            f"HTTP {history.status_code}",
        )
        calendar = client.get(
            f"/api/calendar?from={log_date}&to={log_date}", headers=headers
        )
        check(
            results,
            "Calendar date summary",
            calendar.status_code == 200
            and any(item["date"] == log_date for item in calendar.json()),
            f"HTTP {calendar.status_code}",
        )
        daily_stats = client.get(f"/api/stats/daily/{log_date}", headers=headers)
        check(
            results,
            "Daily statistics",
            daily_stats.status_code == 200 and daily_stats.json().get("log_count") == 2,
            f"HTTP {daily_stats.status_code}",
        )
        weekly_stats = client.get("/api/stats/weekly", headers=headers)
        monthly_stats = client.get("/api/stats/monthly", headers=headers)
        check(results, "Weekly MongoDB statistics", weekly_stats.status_code == 200, f"HTTP {weekly_stats.status_code}")
        check(results, "Monthly MongoDB statistics", monthly_stats.status_code == 200, f"HTTP {monthly_stats.status_code}")

        yesterday = (now.date() - timedelta(days=1)).isoformat()
        fallback = client.post(
            f"/api/days/{yesterday}/sleep",
            headers=headers,
            json={"sleep_time": "23:00"},
        )
        check(
            results,
            "Next-morning fallback for yesterday",
            fallback.status_code == 200 and fallback.json().get("status") == "COMPLETED",
            f"HTTP {fallback.status_code}",
        )

        for period in ("weekly", "monthly"):
            if use_gemini_fixtures:
                with patch(
                    "backend.routes.insights.generate_period_insight",
                    side_effect=fixture_period_insight,
                ):
                    report = client.get(f"/api/insights/{period}", headers=headers)
                results[f"{period.title()} Gemini live generation"] = {
                    "status": "SKIPPED",
                    "detail": "Fixture mode requested; live provider generation was not called.",
                }
            else:
                report = client.get(f"/api/insights/{period}", headers=headers)
            if report.status_code == 200:
                if not use_gemini_fixtures:
                    results[f"{period.title()} Gemini live generation"] = {"status": "PASS"}
                cached = client.get(f"/api/insights/{period}", headers=headers)
                check(
                    results,
                    f"{period.title()} insight generation, persistence, and cache",
                    cached.status_code == 200
                    and cached.json().get("report_id") == report.json().get("report_id"),
                    f"HTTP {cached.status_code}; "
                    + ("schema fixture used" if use_gemini_fixtures else "live model response"),
                )
            else:
                results[f"{period.title()} Gemini live generation"] = {
                    "status": "BLOCKED",
                    "detail": "Gemini returned an upstream error; route preserved data and returned a controlled response.",
                }
                check(
                    results,
                    f"{period.title()} insight route handles provider failure",
                    report.status_code == 503,
                    f"HTTP {report.status_code}",
                )
                with patch(
                    "backend.routes.insights.generate_period_insight",
                    side_effect=fixture_period_insight,
                ):
                    fixture_report = client.get(f"/api/insights/{period}", headers=headers)
                check(
                    results,
                    f"{period.title()} insight schema and database persistence",
                    fixture_report.status_code == 200
                    and fixture_report.json().get("insight", {}).get("summary"),
                    f"HTTP {fixture_report.status_code}; test fixture used after live Gemini outage",
                )
                cached = client.get(f"/api/insights/{period}", headers=headers)
                check(
                    results,
                    f"{period.title()} insight cache readback",
                    cached.status_code == 200
                    and cached.json().get("report_id") == fixture_report.json().get("report_id"),
                    f"HTTP {cached.status_code}",
                )

        logout = client.post("/api/auth/logout", headers=headers)
        check(results, "Logout revokes session", logout.status_code == 200)
        after_logout = client.get("/api/users/me", headers=headers)
        check(results, "Revoked session cannot access protected data", after_logout.status_code == 401)

    return results


def main() -> int:
    try:
        results = run_scenario()
    except Exception as error:
        results = {"scenario setup/runtime": {"status": "FAIL", "detail": str(error)}}

    passed = sum(item["status"] == "PASS" for item in results.values())
    failed = sum(item["status"] == "FAIL" for item in results.values())
    blocked = sum(item["status"] == "BLOCKED" for item in results.values())
    print(
        json.dumps(
            {
                "test_user": TEST_USER["user_id"],
                "results": results,
                "summary": {"passed": passed, "failed": failed, "blocked": blocked},
            },
            indent=2,
        )
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
