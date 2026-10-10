import io
import sys
import uuid
from pathlib import Path
from unittest.mock import patch

from PIL import Image

_root = str(Path(__file__).resolve().parent.parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

from dotenv import load_dotenv
from fastapi.testclient import TestClient

from backend.main import app
from backend.models.photo_meal import PhotoMealDraftResponse, PhotoMealItem, PhotoMealTotal

load_dotenv(Path(_root) / "backend" / ".env")


def _generate_test_image_bytes(width=800, height=600, fmt="JPEG") -> bytes:
    img = Image.new("RGB", (width, height), color=(200, 100, 50))
    buf = io.BytesIO()
    img.save(buf, format=fmt)
    return buf.getvalue()


def test_m6_photo_meal_analysis_and_logging():
    with TestClient(app) as client:
        # 1. Login
        login_res = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "4321",
        })
        assert login_res.status_code == 200
        headers = {"Authorization": f"Bearer {login_res.json()['access_token']}"}

        # 2. Reject unsupported media type
        text_bytes = b"This is not an image file"
        bad_file_res = client.post(
            "/api/logs/photo/analyze",
            headers=headers,
            files={"image": ("sample.txt", text_bytes, "text/plain")},
        )
        assert bad_file_res.status_code == 415

        # 3. Analyze valid meal photo with Gemini mock
        img_bytes = _generate_test_image_bytes()
        mock_draft = PhotoMealDraftResponse(
            items=[
                PhotoMealItem(name="Paneer Butter Masala", portion="1 bowl (~180g)", protein_g=14.0, calories=320, confidence=0.65),
                PhotoMealItem(name="Butter Tandoori Roti", portion="2 rotis", protein_g=6.0, calories=240, confidence=0.85),
                PhotoMealItem(name="Steamed Rice", portion="1 cup (~150g)", protein_g=3.5, calories=195, confidence=0.90),
            ],
            total=PhotoMealTotal(protein_g=23.5, calories=755),
            notes="Gravy oil content estimated with average restaurant proportions.",
            estimate=True,
        )

        with patch("backend.routes.photo_meal.generate_multimodal_structured") as mock_gemini:
            mock_gemini.return_value = (mock_draft, "gemini-2.5-flash-mock")

            analyze_res = client.post(
                "/api/logs/photo/analyze",
                headers=headers,
                files={"image": ("plate.jpg", img_bytes, "image/jpeg")},
                data={"text": "ate half of the rice"},
            )
            assert analyze_res.status_code == 200, f"Analyze failed: {analyze_res.text}"
            draft = analyze_res.json()
            assert draft["estimate"] is True
            assert len(draft["items"]) == 3
            assert draft["total"]["protein_g"] == 23.5
            assert draft["total"]["calories"] == 755
            assert mock_gemini.call_count == 1

        # 4. User confirms / edits draft -> Logs via POST /api/logs/structured with source: "photo"
        client_id = f"photo-log-{uuid.uuid4()}"
        summary_text = "Photo: " + ", ".join(item["name"] for item in draft["items"])
        log_res = client.post(
            "/api/logs/structured",
            headers=headers,
            json={
                "text": summary_text,
                "extracted": {
                    "protein_g": draft["total"]["protein_g"],
                    "calories": draft["total"]["calories"],
                    "calories_kcal": draft["total"]["calories"],
                },
                "source": "photo",
                "client_id": client_id,
                "meta": {
                    "item_count": len(draft["items"]),
                    "estimate": True,
                },
            },
        )
        assert log_res.status_code == 201, f"Structured log failed: {log_res.text}"
        log_data = log_res.json()
        assert log_data["source"] == "photo"
        assert log_data["extraction_status"] == "done"
        assert log_data["extracted"]["protein_g"] == 23.5
        assert log_data["extracted"]["calories"] == 755

        # Cleanup test log
        client.delete(f"/api/logs/{log_data['id']}", headers=headers)
        print("ALL M6 PHOTO MEAL LOGGING TESTS PASSED SUCCESSFULLY!")


if __name__ == "__main__":
    test_m6_photo_meal_analysis_and_logging()
