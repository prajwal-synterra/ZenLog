import asyncio
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path

# Ensure project root is on sys.path so "from backend..." imports succeed from any cwd
_project_root = str(Path(__file__).resolve().parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pymongo import MongoClient
from pymongo.server_api import ServerApi

from backend.routes.auth import router as auth_router
from backend.routes.calendar import router as calendar_router
from backend.routes.day_view import router as day_view_router
from backend.routes.days import router as days_router
from backend.routes.export import router as export_router
from backend.routes.health import router as health_router
from backend.routes.insights import router as insights_router
from backend.routes.logs import router as logs_router
from backend.routes.quotes import router as quotes_router
from backend.routes.stats import router as stats_router
from backend.routes.users import router as users_router
from backend.services.quote_service import seed_default_quotes



async def _sweeper_loop(database):
    """Runs every 5 minutes, re-enqueues stuck pending log extractions."""
    from backend.ai.entry_extraction import sweeper
    while True:
        try:
            await asyncio.sleep(300)  # 5 minutes
            await sweeper(database)
        except asyncio.CancelledError:
            break
        except Exception:
            pass  # Never crash the server over a sweeper error


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_dotenv(Path(__file__).resolve().parent / ".env")
    mongo_uri = os.getenv("MONGODB_URI") or os.getenv("MONGO_URI")
    if not mongo_uri:
        raise RuntimeError("Set MONGODB_URI or MONGO_URI in the environment or .env file.")

    client = MongoClient(
        mongo_uri,
        server_api=ServerApi("1"),
        serverSelectionTimeoutMS=5000,
        tz_aware=True,
    )
    try:
        client.admin.command("ping")
    except Exception:
        client.close()
        raise

    db = client[os.getenv("MONGODB_DATABASE", "zenlog")]
    app.state.mongo_client = client
    app.state.database = db

    # --- Indexes ---
    # Users
    db["users"].create_index("user_id", unique=True, name="user_id_unique")
    db["users"].create_index("username", unique=True, name="username_unique")

    # Sessions
    db["sessions"].create_index("token_hash", unique=True, name="session_token_unique")
    db["sessions"].create_index("expires_at", expireAfterSeconds=0, name="session_expiry_ttl")

    # Login attempts (brute-force protection with 15-minute TTL)
    db["login_attempts"].create_index(
        "created_at",
        expireAfterSeconds=900,
        name="login_attempts_ttl",
    )
    db["login_attempts"].create_index(
        [("username", 1), ("ip", 1), ("created_at", -1)],
        name="login_attempts_lookup",
    )

    db["daily_logs"].create_index(
        [("user_id", 1), ("date", 1), ("timestamp", 1)],
        name="user_date_timestamp",
    )
    db["daily_logs"].create_index(
        [("user_id", 1), ("logical_date", 1)],
        name="user_logical_date",
    )
    db["daily_logs"].create_index(
        [("extraction_status", 1), ("updated_at", 1)],
        name="extraction_sweeper",
    )
    try:
        db["daily_logs"].drop_index("user_client_id_unique")
    except Exception:
        pass
    db["daily_logs"].create_index(
        [("user_id", 1), ("client_id", 1)],
        unique=True,
        partialFilterExpression={"client_id": {"$type": "string"}},
        name="user_client_id_unique",
    )


    # Days (v2)
    db["days"].create_index(
        [("user_id", 1), ("date", 1)],
        unique=True,
        name="days_user_date_unique",
    )

    # Legacy daily_records (kept for backward compat, not used by v2 write paths)
    db["daily_records"].create_index(
        [("user_id", 1), ("date", 1)],
        unique=True,
        name="user_date_unique",
    )

    # Reports
    db["reports"].create_index(
        [("user_id", 1), ("period", 1), ("period_start", 1)],
        unique=True,
        name="user_period_unique",
    )

    # Daily quotes (24-hour cache per user per date)
    db["daily_quotes"].create_index(
        [("user_id", 1), ("date", 1)],
        unique=True,
        name="daily_quotes_user_date_unique",
    )

    # Pre-seed default quotes pool if empty
    seed_default_quotes(db)

    # --- Run startup sweeper (catch stuck pending logs from last server run) ---
    from backend.ai.entry_extraction import sweeper as run_sweeper
    asyncio.create_task(run_sweeper(db))

    # --- Start periodic sweeper ---
    sweeper_task = asyncio.create_task(_sweeper_loop(db))

    # --- Start keep-alive loop (Module 1 Render stay-awake) ---
    from backend.services.keepalive import keepalive_loop
    keepalive_task = asyncio.create_task(keepalive_loop())

    try:
        yield
    finally:
        keepalive_task.cancel()
        sweeper_task.cancel()
        client.close()


app = FastAPI(title="ZenLog API", version="2.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(auth_router)
app.include_router(logs_router)
app.include_router(day_view_router)   # New v2 day view (mounted before legacy days router)
app.include_router(days_router)       # Legacy: /api/days/prompt-status, wake, sleep, etc.
app.include_router(quotes_router)     # Quotes: /api/quotes/{day}
app.include_router(users_router)
app.include_router(calendar_router)
app.include_router(stats_router)
app.include_router(insights_router)
app.include_router(export_router)