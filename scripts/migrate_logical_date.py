"""
Module 2: Migration script for existing logs without logged_at / logical_date.
Sets logged_at from timestamp/created_at, computes logical_date in IST (4 AM rule),
and sets source: 'text'.
"""
import os
import sys
from pathlib import Path

_root = str(Path(__file__).resolve().parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

from datetime import datetime, timezone
from dotenv import load_dotenv
from pymongo import MongoClient

from backend.core.timeutil import IST, logical_date


def migrate():
    load_dotenv(Path(_root) / "backend" / ".env")
    uri = os.getenv("MONGODB_URI") or os.getenv("MONGO_URI")
    if not uri:
        print("MONGODB_URI not found.")
        return

    client = MongoClient(uri)
    db = client[os.getenv("MONGODB_DATABASE", "zenlog")]
    collection = db["daily_logs"]

    cursor = collection.find({
        "$or": [
            {"logical_date": {"$exists": False}},
            {"logged_at": {"$exists": False}},
            {"source": {"$exists": False}},
        ]
    })

    count = 0
    for doc in cursor:
        ts = doc.get("timestamp") or doc.get("created_at")
        if ts is None:
            ts = datetime.now(timezone.utc)
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)

        ts_ist = ts.astimezone(IST)
        calc_logical_date = logical_date(ts_ist)

        update = {
            "logged_at": ts,
            "logical_date": calc_logical_date,
            "date": calc_logical_date,
            "tz": "Asia/Kolkata",
            "source": doc.get("source") or "text",
            "meta": doc.get("meta") or {},
        }
        collection.update_one({"_id": doc["_id"]}, {"$set": update})
        count += 1

    print(f"Successfully migrated {count} logs to M2 schema.")
    client.close()


if __name__ == "__main__":
    migrate()
