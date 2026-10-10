import io
import re
import uuid
from datetime import datetime, timezone
from typing import Any

from bson import ObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from PIL import Image, ImageOps
from pymongo.database import Database
from pydantic import BaseModel, Field

from backend.ai.gemini_client import generate_multimodal_structured, generate_structured
from backend.core.label_validation import validate_nutrition
from backend.core.scoring import detect_flags, score_product
from backend.core.timeutil import IST, logical_date, now_ist
from backend.models.food_scan import (
    EvaluateScanRequest,
    EvaluateScanResponse,
    NutritionValues,
    ProductLogRequest,
    ProductMeta,
    ProductResponse,
    SaveProductRequest,
    ScanLogRequest,
    ScanResultResponse,
    UpdateScanRequest,
    ValidationResult,
)
from backend.routes.dependencies import get_auth_context, get_database
from backend.routes.logs import serialize_log, touch_day
from backend.services.close_service import get_user_targets_snapshot
from backend.services.progress_engine import compute_day_totals

router = APIRouter(prefix="/api/foods", tags=["food_scan"])

MAX_IMAGE_BYTES = 3 * 1024 * 1024
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}


class _GeminiLabelExtraction(BaseModel):
    product_name: str = Field(default="Packaged Food", description="Product name")
    brand: str = Field(default="", description="Brand name")
    pack_size_g: float | None = Field(default=None, description="Pack net weight in grams or ml")
    serving_size_g: float | None = Field(default=None, description="Serving size in grams or ml")
    servings_per_pack: float | None = Field(default=None, description="Servings per pack")
    is_liquid: bool = Field(default=False, description="True if product is a liquid/drink")

    # Column 1: Per 100g / 100ml
    per_100g_energy_kcal: float | None = None
    per_100g_protein_g: float | None = None
    per_100g_carbs_g: float | None = None
    per_100g_sugar_g: float | None = None
    per_100g_added_sugar_g: float | None = None
    per_100g_fat_g: float | None = None
    per_100g_sat_fat_g: float | None = None
    per_100g_trans_fat_g: float | None = None
    per_100g_fiber_g: float | None = None
    per_100g_sodium_mg: float | None = None
    per_100g_salt_g: float | None = None

    # Column 2: Per serving
    per_serving_energy_kcal: float | None = None
    per_serving_protein_g: float | None = None
    per_serving_carbs_g: float | None = None
    per_serving_sugar_g: float | None = None
    per_serving_added_sugar_g: float | None = None
    per_serving_fat_g: float | None = None
    per_serving_sat_fat_g: float | None = None
    per_serving_trans_fat_g: float | None = None
    per_serving_fiber_g: float | None = None
    per_serving_sodium_mg: float | None = None

    ingredients: list[str] = Field(default_factory=list, description="Ingredients in printed order")
    confidence: float = Field(default=0.85, description="OCR extraction confidence (0.0 to 1.0)")


def _clean_image(file_bytes: bytes, content_type: str) -> tuple[bytes, str]:
    if len(file_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Image size exceeds 3 MB limit.",
        )
    if content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported format ({content_type}). Use JPEG, PNG, or WebP.",
        )
    try:
        with Image.open(io.BytesIO(file_bytes)) as img:
            img = ImageOps.exif_transpose(img)
            img = img.convert("RGB")
            max_dim = 1600
            if max(img.size) > max_dim:
                img.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
            buffer = io.BytesIO()
            img.save(buffer, format="JPEG", quality=85, optimize=True)
            return buffer.getvalue(), "image/jpeg"
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Corrupted image: {str(e)}",
        ) from None


def _normalize_extracted(raw: _GeminiLabelExtraction) -> tuple[ProductMeta, NutritionValues, NutritionValues | None]:
    product = ProductMeta(
        name=raw.product_name or "Packaged Food",
        brand=raw.brand or "",
        pack_size_g=raw.pack_size_g,
        serving_size_g=raw.serving_size_g,
        servings_per_pack=raw.servings_per_pack,
        is_liquid=raw.is_liquid,
    )

    per_100 = NutritionValues(
        energy_kcal=raw.per_100g_energy_kcal,
        protein_g=raw.per_100g_protein_g,
        carbs_g=raw.per_100g_carbs_g,
        sugar_g=raw.per_100g_sugar_g,
        added_sugar_g=raw.per_100g_added_sugar_g,
        fat_g=raw.per_100g_fat_g,
        sat_fat_g=raw.per_100g_sat_fat_g,
        trans_fat_g=raw.per_100g_trans_fat_g,
        fiber_g=raw.per_100g_fiber_g,
        sodium_mg=raw.per_100g_sodium_mg,
    )

    # Salt to sodium conversion: sodium_mg ≈ salt_g * 400
    if per_100.sodium_mg is None and raw.per_100g_salt_g is not None:
        per_100.sodium_mg = round(raw.per_100g_salt_g * 400.0, 1)

    per_serving: NutritionValues | None = None
    has_serving_data = any([
        raw.per_serving_energy_kcal is not None,
        raw.per_serving_protein_g is not None,
        raw.per_serving_carbs_g is not None,
        raw.per_serving_fat_g is not None,
    ])
    if has_serving_data:
        per_serving = NutritionValues(
            energy_kcal=raw.per_serving_energy_kcal,
            protein_g=raw.per_serving_protein_g,
            carbs_g=raw.per_serving_carbs_g,
            sugar_g=raw.per_serving_sugar_g,
            added_sugar_g=raw.per_serving_added_sugar_g,
            fat_g=raw.per_serving_fat_g,
            sat_fat_g=raw.per_serving_sat_fat_g,
            trans_fat_g=raw.per_serving_trans_fat_g,
            fiber_g=raw.per_serving_fiber_g,
            sodium_mg=raw.per_serving_sodium_mg,
        )

    # If only per_serving is present and serving_size_g is known, derive per_100g
    if per_100.energy_kcal is None and per_serving and raw.serving_size_g and raw.serving_size_g > 0:
        factor = 100.0 / raw.serving_size_g
        per_100 = NutritionValues(
            energy_kcal=round(per_serving.energy_kcal * factor, 1) if per_serving.energy_kcal else None,
            protein_g=round(per_serving.protein_g * factor, 1) if per_serving.protein_g else None,
            carbs_g=round(per_serving.carbs_g * factor, 1) if per_serving.carbs_g else None,
            sugar_g=round(per_serving.sugar_g * factor, 1) if per_serving.sugar_g else None,
            added_sugar_g=round(per_serving.added_sugar_g * factor, 1) if per_serving.added_sugar_g else None,
            fat_g=round(per_serving.fat_g * factor, 1) if per_serving.fat_g else None,
            sat_fat_g=round(per_serving.sat_fat_g * factor, 1) if per_serving.sat_fat_g else None,
            trans_fat_g=round(per_serving.trans_fat_g * factor, 2) if per_serving.trans_fat_g else None,
            fiber_g=round(per_serving.fiber_g * factor, 1) if per_serving.fiber_g else None,
            sodium_mg=round(per_serving.sodium_mg * factor, 1) if per_serving.sodium_mg else None,
        )

    return product, per_100, per_serving


@router.post("/scan", response_model=ScanResultResponse)
async def scan_food_label(
    images: list[UploadFile] = File(default=[]),
    ocr_text: str | None = Form(default=None),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Module 7: Label scanner & rating.
    - Accepts 1–3 images of the nutrition table / ingredients.
    - If on-device OCR text is provided, parses with high speed.
    - Fallback: multimodal Gemini vision analysis.
    - Returns structured numbers, transparent 0–100 score, flags, and sanity checks.
    """
    user_id = auth_context["user"]["user_id"]
    goal = auth_context["user"].get("goal", "muscle_gain")

    raw_extracted: _GeminiLabelExtraction | None = None
    ocr_source = "gemini_vision"

    # 1. Hybrid Mode: If high-confidence on-device OCR text is provided
    if ocr_text and len(ocr_text.strip()) > 30:
        ocr_source = "local_ocr"
        prompt = (
            "You are a nutritional data extraction engine.\n"
            "Extract structured values strictly from this recognized food packaging text:\n"
            f"```\n{ocr_text}\n```\n"
            "Rules:\n"
            "- Return values printed on the label. Use null for anything missing.\n"
            "- Extract per 100g/ml and per serving columns if present.\n"
            "- Return ingredients list in printed order."
        )
        try:
            raw_extracted, _ = generate_structured(_GeminiLabelExtraction, prompt)
        except Exception:
            # Fall back to multimodal vision if text-only parse fails
            raw_extracted = None

    # 2. Multimodal Vision Mode: Analyze uploaded images directly
    if raw_extracted is None:
        ocr_source = "gemini_vision"
        if not images:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="At least one nutrition label image is required.",
            )
        if len(images) > 3:
            images = images[:3]

        prepared_images: list[tuple[bytes, str]] = []
        for img in images:
            b = await img.read()
            cleaned, mime = _clean_image(b, img.content_type or "image/jpeg")
            prepared_images.append((cleaned, mime))

        prompt = (
            "You are an expert food label OCR and packaging extraction system.\n"
            "Analyze the nutrition facts table and ingredients in the provided photo(s).\n"
            "Rules:\n"
            "1. Read ONLY values visibly printed on the label. Use null for unreadable or missing values.\n"
            "2. Distinguish per-100g / 100ml values from per-serving values.\n"
            "3. If only kJ energy is shown, convert to kcal (kJ / 4.184).\n"
            "4. If salt is printed instead of sodium, record in salt_g.\n"
            "5. Extract ingredients in printed order.\n"
            "6. Identify product name and brand if visible on pack.\n"
            "7. Assign extraction confidence between 0.0 and 1.0."
        )

        try:
            raw_extracted, _ = generate_multimodal_structured(
                _GeminiLabelExtraction,
                prompt,
                prepared_images,
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Label scanning failed ({str(e)}). Ensure clear lighting and retake photo.",
            ) from None

    # 3. Normalize values
    product, per_100, per_serving = _normalize_extracted(raw_extracted)

    # 4. Sanity validation
    validation = validate_nutrition(per_100)

    # 5. Deterministic Goal-Aware Scoring (v1 heuristic)
    ingredients = raw_extracted.ingredients or []
    flags = detect_flags(ingredients)
    score_res = score_product(per_100, ingredients, goal=goal)

    # 6. Save scan to food_scans collection (with TTL)
    scan_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    scan_doc = {
        "scan_id": scan_id,
        "user_id": user_id,
        "product": product.model_dump(),
        "per_100g": per_100.model_dump(),
        "per_serving": per_serving.model_dump() if per_serving else None,
        "ingredients": ingredients,
        "flags": flags,
        "validation": validation.model_dump(),
        "score": score_res.model_dump(),
        "confidence": raw_extracted.confidence,
        "ocr_source": ocr_source,
        "created_at": now,
    }
    database["food_scans"].insert_one(scan_doc)

    return ScanResultResponse(
        scan_id=scan_id,
        product=product,
        per_100g=per_100,
        per_serving=per_serving,
        ingredients=ingredients,
        flags=flags,
        validation=validation,
        score=score_res,
        confidence=raw_extracted.confidence,
        ocr_source=ocr_source,
    )


@router.put("/scan/{scan_id}", response_model=ScanResultResponse)
def update_scan(
    scan_id: str,
    payload: UpdateScanRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Update user corrections to scan numbers; recalculates score deterministically."""
    user_id = auth_context["user"]["user_id"]
    goal = auth_context["user"].get("goal", "muscle_gain")
    scan = database["food_scans"].find_one({"scan_id": scan_id, "user_id": user_id})
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found.")

    product = ProductMeta.model_validate(payload.product.model_dump() if payload.product else scan["product"])
    if payload.serving_size_g is not None:
        product.serving_size_g = payload.serving_size_g

    per_100 = NutritionValues.model_validate(payload.per_100g.model_dump() if payload.per_100g else scan["per_100g"])
    ingredients = payload.ingredients if payload.ingredients is not None else scan.get("ingredients", [])

    flags = detect_flags(ingredients)
    validation = validate_nutrition(per_100)
    score_res = score_product(per_100, ingredients, goal=goal)

    update_fields = {
        "product": product.model_dump(),
        "per_100g": per_100.model_dump(),
        "ingredients": ingredients,
        "flags": flags,
        "validation": validation.model_dump(),
        "score": score_res.model_dump(),
        "updated_at": datetime.now(timezone.utc),
    }
    database["food_scans"].update_one({"scan_id": scan_id}, {"$set": update_fields})

    return ScanResultResponse(
        scan_id=scan_id,
        product=product,
        per_100g=per_100,
        per_serving=NutritionValues.model_validate(scan["per_serving"]) if scan.get("per_serving") else None,
        ingredients=ingredients,
        flags=flags,
        validation=validation,
        score=score_res,
        confidence=scan.get("confidence", 0.9),
        ocr_source=scan.get("ocr_source", "gemini_vision"),
    )


def _calc_portion_macros(per_100: NutritionValues, product: ProductMeta, servings: float | None, grams: float | None) -> tuple[float, dict, str]:
    if grams is not None and grams > 0:
        total_g = grams
        desc = f"{round(grams, 1)}g"
    elif servings is not None and servings > 0:
        srv_g = product.serving_size_g or 30.0
        total_g = servings * srv_g
        desc = f"{servings} serving{'s' if servings != 1 else ''} ({round(total_g, 1)}g)"
    else:
        srv_g = product.serving_size_g or 100.0
        total_g = srv_g
        desc = f"1 serving ({round(total_g, 1)}g)"

    ratio = total_g / 100.0
    prot = round((per_100.protein_g or 0.0) * ratio, 1)
    kcal = round((per_100.energy_kcal or 0.0) * ratio)
    carbs = round((per_100.carbs_g or 0.0) * ratio, 1)
    fat = round((per_100.fat_g or 0.0) * ratio, 1)

    return total_g, {
        "protein_g": prot,
        "calories": kcal,
        "calories_kcal": kcal,
        "carbs_g": carbs,
        "fat_g": fat,
    }, desc


@router.post("/scan/{scan_id}/evaluate", response_model=EvaluateScanResponse)
def evaluate_scan(
    scan_id: str,
    payload: EvaluateScanRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Calculates portion macros and impact on today's target budget."""
    user = auth_context["user"]
    user_id = user["user_id"]
    scan = database["food_scans"].find_one({"scan_id": scan_id, "user_id": user_id})
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found.")

    per_100 = NutritionValues.model_validate(scan["per_100g"])
    product = ProductMeta.model_validate(scan["product"])
    _, macros, desc = _calc_portion_macros(per_100, product, payload.servings, payload.grams)

    # Today's targets snapshot
    targets = get_user_targets_snapshot(user)
    target_prot = targets.get("protein_g", 0.0)
    target_cal = targets.get("calories_kcal")

    # Load today's logs to get remaining
    today_key = now_ist().date().isoformat()
    today_entries = list(database["daily_logs"].find({"user_id": user_id, "date": today_key}))
    today_totals = compute_day_totals(today_entries)

    current_prot = today_totals.get("protein_g", 0.0)
    current_cal = today_totals.get("calories_kcal", 0.0)

    remaining_prot = max(target_prot - current_prot, 0.0)
    prot_rem_pct = round((macros["protein_g"] / remaining_prot * 100), 1) if remaining_prot > 0 else 100.0
    cal_budget_pct = round((macros["calories"] / target_cal * 100), 1) if target_cal else None

    summary_line = f"Adds {macros['protein_g']}g protein"
    if remaining_prot > 0:
        summary_line += f" ({prot_rem_pct}% of what you still need)"
    if cal_budget_pct is not None:
        summary_line += f" for {macros['calories']} kcal ({cal_budget_pct}% of budget)."
    else:
        summary_line += f" for {macros['calories']} kcal."

    return EvaluateScanResponse(
        scan_id=scan_id,
        amount_description=desc,
        portion_macros=macros,
        day_impact={
            "protein_g": macros["protein_g"],
            "calories_kcal": macros["calories"],
            "protein_remaining_pct": prot_rem_pct,
            "calorie_budget_pct": cal_budget_pct,
            "current_protein_g": current_prot,
            "current_calories_kcal": current_cal,
            "target_protein_g": target_prot,
            "target_calories_kcal": target_cal,
            "summary": summary_line,
        },
    )


@router.post("/scan/{scan_id}/log", status_code=status.HTTP_201_CREATED)
def log_scan_portion(
    scan_id: str,
    payload: ScanLogRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Creates a structured log for the scanned food portion."""
    user = auth_context["user"]
    user_id = user["user_id"]
    scan = database["food_scans"].find_one({"scan_id": scan_id, "user_id": user_id})
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found.")

    per_100 = NutritionValues.model_validate(scan["per_100g"])
    product = ProductMeta.model_validate(scan["product"])
    _, macros, desc = _calc_portion_macros(per_100, product, payload.servings, payload.grams)

    effective_logged_at = payload.logged_at or now_ist()
    day_key = logical_date(effective_logged_at)
    now = datetime.now(timezone.utc)

    client_id = payload.client_id or str(uuid.uuid4())
    log_text = f"Packaged: {product.name} ({desc})"

    document = {
        "user_id": user_id,
        "client_id": client_id,
        "date": day_key,
        "logical_date": day_key,
        "timestamp": effective_logged_at.astimezone(timezone.utc),
        "logged_at": effective_logged_at.astimezone(timezone.utc),
        "tz": "Asia/Kolkata",
        "source": "label",
        "meta": {
            "scan_id": scan_id,
            "product_name": product.name,
            "brand": product.brand,
            "score": scan.get("score", {}).get("value"),
            "grade": scan.get("score", {}).get("grade"),
            "portion_desc": desc,
        },
        "text": log_text,
        "extraction_status": "done",
        "extraction_error": None,
        "extracted_at": now,
        "extracted": {
            "protein_g": macros["protein_g"],
            "calories": macros["calories"],
            "calories_kcal": macros["calories"],
            "carbs_g": macros.get("carbs_g", 0.0),
            "fat_g": macros.get("fat_g", 0.0),
        },
        "overrides": {},
        "created_at": now,
        "updated_at": now,
    }
    result = database["daily_logs"].insert_one(document)
    document["_id"] = result.inserted_id

    touch_day(database, user_id, day_key)
    return serialize_log(document)


@router.post("/products", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
def save_product(
    payload: SaveProductRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Saves a scanned item to 'My Products'."""
    user = auth_context["user"]
    user_id = user["user_id"]
    goal = user.get("goal", "muscle_gain")

    if payload.scan_id:
        scan = database["food_scans"].find_one({"scan_id": payload.scan_id, "user_id": user_id})
        if not scan:
            raise HTTPException(status_code=404, detail="Scan not found.")
        product_meta = ProductMeta.model_validate(scan["product"])
        per_100 = NutritionValues.model_validate(scan["per_100g"])
        ingredients = scan.get("ingredients", [])
        flags = scan.get("flags", [])
        score_data = scan.get("score", {})
    else:
        if not payload.name or not payload.per_100g:
            raise HTTPException(status_code=400, detail="Product name and per_100g macros required.")
        product_meta = ProductMeta(
            name=payload.name,
            brand=payload.brand or "",
            pack_size_g=payload.pack_size_g,
            serving_size_g=payload.serving_size_g,
        )
        per_100 = payload.per_100g
        ingredients = payload.ingredients or []
        flags = detect_flags(ingredients)
        score_res = score_product(per_100, ingredients, goal=goal)
        score_data = score_res.model_dump()

    # Normalize name_key for deduplication
    clean_name = re.sub(r"\s+", " ", product_meta.name.strip().lower())
    name_key = f"{clean_name}|{product_meta.brand.strip().lower()}"
    now = datetime.now(timezone.utc)

    doc = {
        "user_id": user_id,
        "name": product_meta.name,
        "brand": product_meta.brand,
        "name_key": name_key,
        "pack_size_g": product_meta.pack_size_g,
        "serving_size_g": product_meta.serving_size_g,
        "per_100g": per_100.model_dump(),
        "ingredients": ingredients,
        "flags": flags,
        "score": score_data.get("value", 50),
        "grade": score_data.get("grade", "Okay"),
        "times_logged": 0,
        "created_at": now,
        "updated_at": now,
    }

    res = database["products"].find_one_and_update(
        {"user_id": user_id, "name_key": name_key},
        {"$set": doc},
        upsert=True,
        return_document=True,
    )

    return ProductResponse(
        id=str(res["_id"]),
        name=res["name"],
        brand=res.get("brand", ""),
        name_key=res["name_key"],
        pack_size_g=res.get("pack_size_g"),
        serving_size_g=res.get("serving_size_g"),
        per_100g=NutritionValues.model_validate(res["per_100g"]),
        ingredients=res.get("ingredients", []),
        flags=res.get("flags", []),
        score=res.get("score", 50),
        grade=res.get("grade", "Okay"),
        times_logged=res.get("times_logged", 0),
        created_at=res.get("created_at"),
    )


@router.get("/products", response_model=list[ProductResponse])
def list_products(
    q: str = "",
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Lists / searches saved products in My Products."""
    user_id = auth_context["user"]["user_id"]
    query: dict[str, Any] = {"user_id": user_id}
    if q.strip():
        query["name"] = {"$regex": re.escape(q.strip()), "$options": "i"}

    docs = list(database["products"].find(query).sort("times_logged", -1).limit(50))
    results = []
    for d in docs:
        results.append(ProductResponse(
            id=str(d["_id"]),
            name=d["name"],
            brand=d.get("brand", ""),
            name_key=d["name_key"],
            pack_size_g=d.get("pack_size_g"),
            serving_size_g=d.get("serving_size_g"),
            per_100g=NutritionValues.model_validate(d["per_100g"]),
            ingredients=d.get("ingredients", []),
            flags=d.get("flags", []),
            score=d.get("score", 50),
            grade=d.get("grade", "Okay"),
            times_logged=d.get("times_logged", 0),
            created_at=d.get("created_at"),
        ))
    return results


@router.post("/products/{product_id}/log", status_code=status.HTTP_201_CREATED)
def log_saved_product(
    product_id: str,
    payload: ProductLogRequest,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """Logs a saved product by portion with ZERO AI calls."""
    user_id = auth_context["user"]["user_id"]
    try:
        oid = ObjectId(product_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid product ID.")

    product_doc = database["products"].find_one({"_id": oid, "user_id": user_id})
    if not product_doc:
        raise HTTPException(status_code=404, detail="Product not found.")

    per_100 = NutritionValues.model_validate(product_doc["per_100g"])
    product_meta = ProductMeta(
        name=product_doc["name"],
        brand=product_doc.get("brand", ""),
        pack_size_g=product_doc.get("pack_size_g"),
        serving_size_g=product_doc.get("serving_size_g"),
    )
    _, macros, desc = _calc_portion_macros(per_100, product_meta, payload.servings, payload.grams)

    effective_logged_at = payload.logged_at or now_ist()
    day_key = logical_date(effective_logged_at)
    now = datetime.now(timezone.utc)

    client_id = payload.client_id or str(uuid.uuid4())
    log_text = f"{product_doc['name']} ({desc})"

    document = {
        "user_id": user_id,
        "client_id": client_id,
        "date": day_key,
        "logical_date": day_key,
        "timestamp": effective_logged_at.astimezone(timezone.utc),
        "logged_at": effective_logged_at.astimezone(timezone.utc),
        "tz": "Asia/Kolkata",
        "source": "label",
        "meta": {
            "product_id": product_id,
            "product_name": product_doc["name"],
            "score": product_doc.get("score"),
            "grade": product_doc.get("grade"),
            "portion_desc": desc,
        },
        "text": log_text,
        "extraction_status": "done",
        "extraction_error": None,
        "extracted_at": now,
        "extracted": {
            "protein_g": macros["protein_g"],
            "calories": macros["calories"],
            "calories_kcal": macros["calories"],
            "carbs_g": macros.get("carbs_g", 0.0),
            "fat_g": macros.get("fat_g", 0.0),
        },
        "overrides": {},
        "created_at": now,
        "updated_at": now,
    }
    result = database["daily_logs"].insert_one(document)
    document["_id"] = result.inserted_id

    # Increment use count
    database["products"].update_one(
        {"_id": oid},
        {"$inc": {"times_logged": 1}, "$set": {"updated_at": now}},
    )

    touch_day(database, user_id, day_key)
    return serialize_log(document)


@router.delete("/products/{product_id}")
def delete_saved_product(
    product_id: str,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    user_id = auth_context["user"]["user_id"]
    try:
        oid = ObjectId(product_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid product ID.")

    del_res = database["products"].delete_one({"_id": oid, "user_id": user_id})
    if del_res.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Product not found.")
    return {"detail": "Product removed from My Products."}
