import os
from pathlib import Path

from dotenv import load_dotenv
from google import genai


def main() -> None:
    load_dotenv(Path(__file__).resolve().parent / "backend" / ".env")
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("Set GEMINI_API_KEY in backend/.env.")

    primary = os.getenv("GEMINI_MODEL", "gemini-3.1-flash-live-preview")
    fallbacks = os.getenv("GEMINI_FALLBACK_MODELS", "gemini-3.8-flash,gemini-3.1-flash-lite")
    model_names = [primary, *(name.strip() for name in fallbacks.split(",") if name.strip())]
    client = genai.Client(api_key=api_key)
    available = {
        model.name.rstrip("/").split("/")[-1]: model
        for model in client.models.list()
    }

    for model_name in model_names:
        model = available.get(model_name)
        if model is None:
            raise RuntimeError(f"Configured model is not available: {model_name}")
        actions = getattr(model, "supported_actions", []) or []
        required_action = "bidiGenerateContent" if "live" in model_name else "generateContent"
        if required_action not in actions:
            raise RuntimeError(f"{model_name} does not support {required_action}.")
        print(f"{model_name}: available and supports {required_action}")


if __name__ == "__main__":
    main()
