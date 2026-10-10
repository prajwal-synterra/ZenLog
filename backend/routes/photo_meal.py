import io
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from PIL import Image, ImageOps
from pymongo.database import Database

from backend.ai.gemini_client import generate_multimodal_structured
from backend.models.photo_meal import PhotoMealDraftResponse, PhotoMealTotal
from backend.routes.dependencies import get_auth_context, get_database

router = APIRouter(prefix="/api/logs/photo", tags=["photo_meal"])

MAX_IMAGE_BYTES = 3 * 1024 * 1024  # 3 MB
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}


def _preprocess_image(file_bytes: bytes, content_type: str) -> tuple[bytes, str]:
    if len(file_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Image size exceeds 3 MB limit.",
        )
    if content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported image type ({content_type}). Use JPEG, PNG, or WebP.",
        )

    try:
        with Image.open(io.BytesIO(file_bytes)) as img:
            # Handle orientation from EXIF then strip metadata
            img = ImageOps.exif_transpose(img)
            img = img.convert("RGB")

            # Resize if dimensions exceed 1280px while maintaining aspect ratio
            max_dim = 1280
            if max(img.size) > max_dim:
                img.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)

            buffer = io.BytesIO()
            img.save(buffer, format="JPEG", quality=85, optimize=True)
            return buffer.getvalue(), "image/jpeg"
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid or corrupted image: {str(e)}",
        ) from None


@router.post("/analyze", response_model=PhotoMealDraftResponse)
async def analyze_meal_photo(
    image: UploadFile = File(...),
    text: str | None = Form(default=None),
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Module 6: Photo meal logging endpoint.
    - Validates image type (JPEG/PNG/WebP) and size (<= 3 MB).
    - Strips EXIF metadata and resizes for fast transmission.
    - Calls Gemini Vision with structured JSON schema.
    - Returns editable draft. Does NOT save a log and does NOT store image bytes.
    """
    user_id = auth_context["user"]["user_id"]

    raw_bytes = await image.read()
    content_type = image.content_type or "image/jpeg"
    clean_bytes, mime = _preprocess_image(raw_bytes, content_type)

    hint = (text or "").strip()
    hint_prompt = f"User notes/hints: '{hint}'." if hint else "No user notes provided."

    prompt = (
        "You are an expert nutrition and visual food estimation assistant.\n"
        "Analyze the provided photo of a meal plate or food dish.\n"
        "Rules:\n"
        "1. Identify distinct food items visible on the plate.\n"
        "2. Estimate portion size in everyday household units (e.g. '1 katori (~150 g)', '2 medium rotis', '1 cup cooked rice (~160 g)').\n"
        "3. Estimate protein in grams and energy in calories for each item.\n"
        "4. Assign confidence (0.0 to 1.0) per item. Oily gravies or hidden fillings should have confidence ~0.5–0.7.\n"
        "5. NEVER invent foods not visibly present.\n"
        f"6. {hint_prompt} Apply this hint to the portions (e.g. if 'ate half', scale down portions and macros accordingly).\n"
        "7. If no food is visible in the photo, return an empty items list and notes: 'I couldn't find food in this photo'.\n"
        "8. Compute total protein and total calories across all items."
    )

    try:
        draft, model_name = generate_multimodal_structured(
            PhotoMealDraftResponse,
            prompt,
            [(clean_bytes, mime)],
        )

        # Ensure total is accurate
        tot_protein = round(sum(item.protein_g for item in draft.items), 1)
        tot_calories = sum(item.calories for item in draft.items)
        draft.total = PhotoMealTotal(protein_g=tot_protein, calories=tot_calories)
        draft.estimate = True

        return draft
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Photo meal analysis unavailable ({str(e)}). Please try again or log manually.",
        ) from None
