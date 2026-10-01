import hashlib
from datetime import datetime, timezone

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pymongo.database import Database


bearer_scheme = HTTPBearer(auto_error=False)


def get_database(request: Request) -> Database:
    return request.app.state.database


def get_auth_context(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    database: Database = Depends(get_database),
) -> dict:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired session.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized

    token_hash = hashlib.sha256(credentials.credentials.encode("utf-8")).hexdigest()
    session = database["sessions"].find_one(
        {
            "token_hash": token_hash,
            "revoked": {"$ne": True},
            "expires_at": {"$gt": datetime.now(timezone.utc)},
        }
    )
    if session is None:
        raise unauthorized

    user = database["users"].find_one(
        {"user_id": session["user_id"]},
        {"_id": 0, "phone_number": 0, "phone": 0},
    )
    if user is None:
        raise unauthorized

    return {"token_hash": token_hash, "user": user}