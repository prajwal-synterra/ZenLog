import json
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

from backend.core.label_validation import validate_nutrition
from backend.core.scoring import detect_flags, score_product
from backend.main import app
from backend.models.food_scan import NutritionValues
from backend.routes.food_scan import _GeminiLabelExtraction

load_dotenv(Path(_root) / "backend" / ".env")


def _generate_test_image_bytes(width=800, height=600) -> bytes:
    img = Image.new("RGB", (width, height), color=(240, 240, 240))
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def test_product_fixture_ranking():
    """Module 7: Asserts expected score rank order across known fixture products."""
    fixture_path = Path(__file__).parent / "fixtures" / "products.json"
    with open(fixture_path, "r", encoding="utf-8") as f:
        products = json.load(f)

    for item in products:
        n = NutritionValues(
            energy_kcal=item.get("energy_kcal"),
            protein_g=item.get("protein_g"),
            carbs_g=item.get("carbs_g"),
            sugar_g=item.get("sugar_g"),
            fat_g=item.get("fat_g"),
            sat_fat_g=item.get("sat_fat_g"),
            fiber_g=item.get("fiber_g"),
            sodium_mg=item.get("sodium_mg"),
        )
        score_res = score_product(n, item.get("ingredients", []), goal="muscle_gain")
        val = score_res.value

        if "expected_min_score" in item:
            assert val >= item["expected_min_score"], f"{item['name']}: got {val}, expected >= {item['expected_min_score']}"
        if "expected_max_score" in item:
            assert val <= item["expected_max_score"], f"{item['name']}: got {val}, expected <= {item['expected_max_score']}"


def test_label_validation_sanity():
    """Module 7: Tests energy mismatch and macro anomaly flags."""
    # 1. Impossible calories mismatch (4*(10+20) + 9*5 = 165 kcal vs printed 300 kcal -> >25% diff)
    bad_energy = NutritionValues(
        energy_kcal=300.0,
        protein_g=10.0,
        carbs_g=20.0,
        fat_g=5.0,
    )
    val1 = validate_nutrition(bad_energy)
    assert "energy_mismatch" in val1.warnings
    assert val1.ok is False

    # 2. Sugar > Carbs
    bad_sugar = NutritionValues(
        energy_kcal=200.0,
        protein_g=5.0,
        carbs_g=10.0,
        sugar_g=25.0,
        fat_g=5.0,
    )
    val2 = validate_nutrition(bad_sugar)
    assert "sugar_gt_carbs" in val2.warnings

    # 3. Additive flag detection
    flags = detect_flags(["Refined wheat flour", "Palm oil", "Invert sugar syrup", "INS 150d", "INS 621"])
    assert "Palm Oil" in flags
    assert any("MSG" in f or "Glutamate" in f for f in flags)


def test_m7_food_scan_and_products_flow():
    with TestClient(app) as client:
        # 1. Login
        login_res = client.post("/api/auth/login", json={
            "username": "testuser1",
            "pin": "4321",
        })
        assert login_res.status_code == 200
        headers = {"Authorization": f"Bearer {login_res.json()['access_token']}"}

        # 2. POST /api/foods/scan (multimodal label scan)
        img_bytes = _generate_test_image_bytes()
        mock_raw = _GeminiLabelExtraction(
            product_name="Peanut Butter Crunch",
            brand="ZenNut",
            pack_size_g=350.0,
            serving_size_g=32.0,
            servings_per_pack=10.9,
            per_100g_energy_kcal=625.0,
            per_100g_protein_g=28.0,
            per_100g_carbs_g=20.0,
            per_100g_sugar_g=6.0,
            per_100g_fat_g=48.0,
            per_100g_sat_fat_g=9.0,
            per_100g_fiber_g=8.0,
            per_100g_sodium_mg=180.0,
            ingredients=["Roasted Peanuts", "Hydrogenated Palm Oil", "Salt"],
            confidence=0.92,
        )

        with patch("backend.routes.food_scan.generate_multimodal_structured") as mock_gemini:
            mock_gemini.return_value = (mock_raw, "gemini-2.5-flash-mock")

            scan_res = client.post(
                "/api/foods/scan",
                headers=headers,
                files={"images": ("label.jpg", img_bytes, "image/jpeg")},
            )
            assert scan_res.status_code == 200, f"Scan failed: {scan_res.text}"
            scan_data = scan_res.json()
            scan_id = scan_data["scan_id"]
            assert scan_data["product"]["name"] == "Peanut Butter Crunch"
            assert scan_data["per_100g"]["protein_g"] == 28.0
            assert scan_data["score"]["value"] > 0
            assert "Palm Oil" in scan_data["flags"]

        # 3. Hybrid local OCR mode test (using ocr_text parameter)
        with patch("backend.routes.food_scan.generate_structured") as mock_text_gemini:
            mock_text_gemini.return_value = (mock_raw, "gemini-2.5-flash-mock")
            local_scan_res = client.post(
                "/api/foods/scan",
                headers=headers,
                data={"ocr_text": "NUTRITION FACTS: Energy 625 kcal, Protein 28g, Carbs 20g, Fat 48g. Ingredients: Peanuts, Salt."},
            )
            assert local_scan_res.status_code == 200
            assert local_scan_res.json()["ocr_source"] == "local_ocr"

        # 4. PUT /api/foods/scan/{scan_id} (user corrections)
        put_res = client.put(
            f"/api/foods/scan/{scan_id}",
            headers=headers,
            json={
                "serving_size_g": 35.0,
                "per_100g": {
                    "energy_kcal": 625.0,
                    "protein_g": 30.0,
                    "carbs_g": 20.0,
                    "sugar_g": 5.0,
                    "fat_g": 48.0,
                    "sat_fat_g": 8.0,
                    "fiber_g": 9.0,
                    "sodium_mg": 180.0,
                },
            },
        )
        assert put_res.status_code == 200
        assert put_res.json()["per_100g"]["protein_g"] == 30.0
        assert put_res.json()["product"]["serving_size_g"] == 35.0

        # 5. POST /api/foods/scan/{scan_id}/evaluate (portion evaluation)
        eval_res = client.post(
            f"/api/foods/scan/{scan_id}/evaluate",
            headers=headers,
            json={"servings": 2.0},
        )
        assert eval_res.status_code == 200
        eval_data = eval_res.json()
        assert eval_data["portion_macros"]["protein_g"] == 21.0  # 2 * 35g = 70g -> 70% of 30g = 21g
        assert "summary" in eval_data["day_impact"]

        # 6. POST /api/foods/scan/{scan_id}/log (log scanned portion)
        log_res = client.post(
            f"/api/foods/scan/{scan_id}/log",
            headers=headers,
            json={"servings": 1.0, "client_id": f"label-cid-{uuid.uuid4()}"},
        )
        assert log_res.status_code == 201
        created_log = log_res.json()
        assert created_log["source"] == "label"
        assert created_log["extracted"]["protein_g"] == 10.5

        # 7. POST /api/foods/products (save to My Products)
        save_prod_res = client.post(
            "/api/foods/products",
            headers=headers,
            json={"scan_id": scan_id},
        )
        assert save_prod_res.status_code == 201
        prod_data = save_prod_res.json()
        product_id = prod_data["id"]
        assert prod_data["name"] == "Peanut Butter Crunch"

        # 8. GET /api/foods/products (search / list)
        list_res = client.get("/api/foods/products?q=Peanut", headers=headers)
        assert list_res.status_code == 200
        assert len(list_res.json()) >= 1

        # 9. POST /api/foods/products/{id}/log (log saved product with 0 AI calls)
        saved_log_res = client.post(
            f"/api/foods/products/{product_id}/log",
            headers=headers,
            json={"grams": 70.0, "client_id": f"saved-prod-cid-{uuid.uuid4()}"},
        )
        assert saved_log_res.status_code == 201
        saved_log_data = saved_log_res.json()
        assert saved_log_data["source"] == "label"
        assert saved_log_data["extracted"]["protein_g"] == 21.0

        # 10. DELETE /api/foods/products/{id}
        del_res = client.delete(f"/api/foods/products/{product_id}", headers=headers)
        assert del_res.status_code == 200

        # Cleanup created logs
        client.delete(f"/api/logs/{created_log['id']}", headers=headers)
        client.delete(f"/api/logs/{saved_log_data['id']}", headers=headers)

        print("ALL M7 FOOD LABEL SCAN & RATING TESTS PASSED SUCCESSFULLY!")


if __name__ == "__main__":
    test_product_fixture_ranking()
    test_label_validation_sanity()
    test_m7_food_scan_and_products_flow()
