from datetime import datetime, timezone
from fastapi import APIRouter, Request, status
from fastapi.responses import JSONResponse
from pymongo.errors import PyMongoError


router = APIRouter(tags=["health"])


@router.get("/ping")
def ping():
    """Ultra-fast keep-alive and cold-start check. Touches NO database."""
    return {"ok": True}


@router.get("/health")
def health(request: Request):
    now_iso = datetime.now(timezone.utc).isoformat()
    try:
        request.app.state.mongo_client.admin.command("ping")
        return {"status": "ok", "database": "connected", "server_time": now_iso}
    except Exception:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "degraded", "database": "disconnected", "server_time": now_iso},
        )