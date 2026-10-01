from datetime import date as date_type
from fastapi import APIRouter, Depends
from pymongo.database import Database

from backend.routes.dependencies import get_auth_context, get_database
from backend.services.quote_service import get_or_create_daily_quote

router = APIRouter(prefix="/api/quotes", tags=["quotes"])


@router.get("/{day}")
def get_quote_for_day(
    day: date_type,
    auth_context: dict = Depends(get_auth_context),
    database: Database = Depends(get_database),
):
    """
    Returns the 24-hour motivational quote for the given date.
    Fetches once from RapidAPI per date, cached in DB for 24h,
    with automatic fallback to default quotes pool if API fails.
    """
    user_id = auth_context["user"]["user_id"]
    day_key = day.isoformat()
    return get_or_create_daily_quote(database, user_id, day_key)
