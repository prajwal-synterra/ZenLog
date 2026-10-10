import re
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Request, status
from passlib.context import CryptContext
from pymongo.database import Database

# CryptContext configured with bcrypt and pbkdf2_sha256
pwd_context = CryptContext(schemes=["bcrypt", "pbkdf2_sha256"], deprecated="auto")

LOCKOUT_THRESHOLD = 5
LOCKOUT_WINDOW_MINUTES = 15


def hash_pin(pin: str) -> str:
    """Hash a numeric PIN securely using salted bcrypt."""
    cleaned = str(pin).strip()
    if not re.match(r"^\d{4,8}$", cleaned):
        raise ValueError("PIN must be between 4 and 8 digits.")
    return pwd_context.hash(cleaned)


def verify_pin(plain_pin: str, hashed_pin: str) -> bool:
    """Verify a plain PIN against a stored hash in constant time."""
    if not plain_pin or not hashed_pin:
        return False
    try:
        return pwd_context.verify(str(plain_pin).strip(), hashed_pin)
    except Exception:
        return False


def get_client_ip(request: Request) -> str:
    """Extract real client IP from headers (behind Render/proxies) or client host."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        # First IP in the list is the actual client
        return forwarded.split(",")[0].strip()
    real_ip = request.headers.get("x-real-ip")
    if real_ip:
        return real_ip.strip()
    if request.client and request.client.host:
        return request.client.host
    return "127.0.0.1"


def check_login_rate_limit(database: Database, username: str, ip: str) -> None:
    """
    Checks if there are 5 or more failed login attempts for this username/ip
    within the last 15 minutes. Raises HTTP 429 if locked out.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=LOCKOUT_WINDOW_MINUTES)
    failed_count = database["login_attempts"].count_documents({
        "username": username.lower().strip(),
        "ip": ip,
        "success": False,
        "created_at": {"$gte": cutoff},
    })
    if failed_count >= LOCKOUT_THRESHOLD:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed login attempts. Try again in 15 minutes.",
        )


def record_login_attempt(database: Database, username: str, ip: str, success: bool) -> None:
    """
    Records a login attempt. On success, clears existing failed attempts for the user/ip.
    On failure, inserts a failed attempt document.
    """
    normalized = username.lower().strip()
    if success:
        database["login_attempts"].delete_many({
            "username": normalized,
            "ip": ip,
        })
    else:
        database["login_attempts"].insert_one({
            "username": normalized,
            "ip": ip,
            "success": False,
            "created_at": datetime.now(timezone.utc),
        })
