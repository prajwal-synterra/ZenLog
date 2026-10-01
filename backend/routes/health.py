from fastapi import APIRouter, HTTPException, Request, status
from pymongo.errors import PyMongoError


router = APIRouter(tags=["health"])


@router.get("/health")
def health(request: Request):
    try:
        request.app.state.mongo_client.admin.command("ping")
    except PyMongoError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database unavailable.",
        ) from None
    return {"status": "ok", "database": "connected"}