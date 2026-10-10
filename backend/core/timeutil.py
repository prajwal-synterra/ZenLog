from datetime import datetime, timedelta, timezone
try:
    from zoneinfo import ZoneInfo
    IST = ZoneInfo("Asia/Kolkata")
except Exception:
    IST = timezone(timedelta(hours=5, minutes=30), name="IST")

BOUNDARY_HOURS = 4


def logical_date(dt: datetime, tz=IST) -> str:
    """
    dt must be timezone-aware.
    Applies the 4 AM boundary rule in IST:
    00:00–03:59 local time belongs to the previous calendar day.
    04:00–23:59 local time belongs to the current calendar day.
    """
    if dt.tzinfo is None:
        raise ValueError("dt must be timezone-aware")
    local = dt.astimezone(tz)
    return (local - timedelta(hours=BOUNDARY_HOURS)).date().isoformat()


def now_ist() -> datetime:
    """Returns current aware datetime in IST."""
    return datetime.now(IST)
