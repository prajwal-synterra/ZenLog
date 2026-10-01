import os
from pathlib import Path
from typing import TypeVar

from dotenv import load_dotenv
from google import genai
from google.genai import types
from pydantic import BaseModel


T = TypeVar("T", bound=BaseModel)
load_dotenv(Path(__file__).resolve().parents[1] / ".env")


def generate_structured(model: type[T], prompt: str) -> tuple[T, str]:
    api_key = os.getenv("GEMINI_API_KEY")
    primary_model = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
    fallback_models = os.getenv("GEMINI_FALLBACK_MODELS")
    if fallback_models:
        model_names = [primary_model, *(name.strip() for name in fallback_models.split(",") if name.strip())]
    else:
        model_names = [
            primary_model,
            os.getenv("GEMINI_FALLBACK_MODEL", "gemini-3.1-flash-lite"),
        ]
    model_names = list(dict.fromkeys(model_names))
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not configured in backend/.env.")

    client = genai.Client(
        api_key=api_key,
        http_options=types.HttpOptions(
            timeout=15000,
            retry_options=types.HttpRetryOptions(attempts=1),
        ),
    )
    failures = []
    for model_name in model_names:
        try:
            chat = client.chats.create(
                model=model_name,
                config=types.GenerateContentConfig(
                    temperature=0.1,
                    response_mime_type="application/json",
                    response_schema=model,
                ),
            )
            response = chat.send_message(prompt)
            if response.parsed is not None:
                return model.model_validate(response.parsed), model_name
            if response.text:
                return model.model_validate_json(response.text), model_name
            raise ValueError("Gemini returned an empty structured response.")
        except Exception as error:
            failures.append(f"{model_name}: {type(error).__name__}")

    raise RuntimeError("Gemini models failed: " + "; ".join(failures))