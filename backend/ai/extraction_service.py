import json

from backend.ai.gemini_client import generate_structured
from backend.models.extraction import DailyExtraction, InsightReport


EXTRACTION_PROMPT_VERSION = "daily-extraction-v1"
INSIGHT_PROMPT_VERSION = "period-insights-v1"


def extract_day(logs: list[dict]) -> tuple[DailyExtraction, str]:
    source_entries = [
        {"timestamp": log["timestamp"].isoformat(), "text": log["text"]}
        for log in logs
    ]
    prompt = """Extract only facts supported by these private journal entries. Do not invent events, quantities, moods, or habits. Keep unknown food quantities and nutrition values null. Nutrition estimates must be marked estimated and have an honest confidence level. Include a mood only when the user explicitly expresses one. Return every applicable category using the requested JSON schema.\n\nJournal entries:\n""" + json.dumps(source_entries, ensure_ascii=False)
    return generate_structured(DailyExtraction, prompt)


def generate_period_insight(period: str, summary: dict) -> tuple[InsightReport, str]:
    prompt = (
        "Write a practical personal journal insight using only the aggregate data below. "
        "Do not infer medical conclusions or invent events. Keep suggestions grounded and concise. "
        f"The reporting period is {period}. Return the requested JSON schema.\n\n"
        f"Aggregated data:\n{json.dumps(summary, ensure_ascii=False, default=str)}"
    )
    return generate_structured(InsightReport, prompt)