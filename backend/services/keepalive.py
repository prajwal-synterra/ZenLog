import asyncio
import logging
import os
import httpx

logger = logging.getLogger("keepalive")


async def keepalive_loop() -> None:
    """
    Module 1: Server Availability Keep-Alive Loop.
    Pings the public /ping endpoint every 10 minutes to prevent Render from idling.
    """
    if os.getenv("KEEPALIVE_ENABLED", "true").lower() not in ("true", "1", "yes"):
        logger.info("Keep-alive loop disabled via KEEPALIVE_ENABLED.")
        return

    base = (
        os.getenv("RENDER_EXTERNAL_URL")
        or os.getenv("BASE_URL")
        or "https://zenlog-zma5.onrender.com"
    )
    if not base:
        logger.info("Keep-alive skipped: no target URL configured.")
        return

    interval = int(os.getenv("KEEPALIVE_INTERVAL_SEC", "600"))  # 10 minutes
    target = f"{base.rstrip('/')}/ping"
    logger.info(f"Keep-alive loop active. Target: {target}, Interval: {interval}s")

    async with httpx.AsyncClient(timeout=20.0) as client:
        while True:
            await asyncio.sleep(interval)
            try:
                resp = await client.get(target)
                logger.info(f"Keep-alive ping {target} -> {resp.status_code}")
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.warning(f"Keep-alive ping failed (non-fatal): {exc}")
