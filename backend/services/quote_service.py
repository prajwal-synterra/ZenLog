import http.client
import json
import logging
import os
import random
from datetime import datetime, timezone
from pathlib import Path
from dotenv import load_dotenv
from pymongo.database import Database

logger = logging.getLogger(__name__)

DEFAULT_QUOTES = [
    {
        "quote": "Consistency beats intensity. What you do every day matters more than what you do once in a while.",
        "author": "James Clear",
        "category": "consistency",
    },
    {
        "quote": "If you are going through hell, keep going.",
        "author": "Winston Churchill",
        "category": "perseverance",
    },
    {
        "quote": "We do not rise to the level of our expectations, we fall to the level of our training.",
        "author": "Archilochus",
        "category": "discipline",
    },
    {
        "quote": "Waste no more time arguing about what a good man should be. Be one.",
        "author": "Marcus Aurelius",
        "category": "stoicism",
    },
    {
        "quote": "Small disciplines repeated with consistency every day lead to great achievements gained slowly over time.",
        "author": "John C. Maxwell",
        "category": "habits",
    },
    {
        "quote": "It is not the mountain we conquer, but ourselves.",
        "author": "Sir Edmund Hillary",
        "category": "mindset",
    },
    {
        "quote": "Discipline is choosing between what you want now and what you want most.",
        "author": "Abraham Lincoln",
        "category": "discipline",
    },
    {
        "quote": "Do not pray for an easy life, pray for the strength to endure a difficult one.",
        "author": "Bruce Lee",
        "category": "strength",
    },
    {
        "quote": "Action is the foundational key to all success.",
        "author": "Pablo Picasso",
        "category": "action",
    },
    {
        "quote": "The body achieves what the mind believes.",
        "author": "Napoleon Hill",
        "category": "fitness",
    },
    {
        "quote": "You don't have to be extreme, just consistent.",
        "author": "Unknown",
        "category": "consistency",
    },
    {
        "quote": "He who has a why to live can bear almost any how.",
        "author": "Friedrich Nietzsche",
        "category": "purpose",
    },
    {
        "quote": "First say to yourself what you would be; and then do what you have to do.",
        "author": "Epictetus",
        "category": "stoicism",
    },
    {
        "quote": "Energy flows where attention goes.",
        "author": "Tony Robbins",
        "category": "focus",
    },
    {
        "quote": "The only bad workout is the one that didn't happen.",
        "author": "Fitness Proverb",
        "category": "fitness",
    },
]


def seed_default_quotes(database: Database) -> None:
    """Pre-seeds the default_quotes collection if it is currently empty."""
    try:
        quotes_col = database["default_quotes"]
        if quotes_col.count_documents({}) == 0:
            quotes_col.insert_many(DEFAULT_QUOTES)
            logger.info("Pre-seeded default quotes pool in MongoDB.")
    except Exception as e:
        logger.warning(f"Could not seed default quotes: {e}")


def fetch_quote_from_rapidapi() -> dict | None:
    """Calls RapidAPI motivation-quotes4 endpoint with timeout."""
    load_dotenv(Path(__file__).resolve().parent.parent / ".env")
    key = os.getenv("RAPIDAPI_QUOTE_KEY")
    host = os.getenv("RAPIDAPI_QUOTE_HOST", "motivation-quotes4.p.rapidapi.com")

    if not key:
        logger.warning("RAPIDAPI_QUOTE_KEY not configured.")
        return None

    try:
        conn = http.client.HTTPSConnection(host, timeout=5)
        headers = {
            "x-rapidapi-key": key,
            "x-rapidapi-host": host,
        }
        conn.request("GET", "/api", headers=headers)
        res = conn.getresponse()
        if res.status == 200:
            data = json.loads(res.read().decode("utf-8"))
            quote_text = data.get("quote", "").strip()
            author = data.get("author", "Unknown").strip()
            if quote_text:
                return {"quote": quote_text, "author": author}
        logger.warning(f"RapidAPI quote returned status {res.status}")
    except Exception as e:
        logger.warning(f"RapidAPI quote request failed: {e}")
    finally:
        try:
            conn.close()
        except Exception:
            pass
    return None


def get_random_fallback_quote(database: Database | None = None) -> dict:
    """Fetches a random quote from the default_quotes collection, or in-memory list."""
    if database is not None:
        try:
            sample = list(database["default_quotes"].aggregate([{"$sample": {"size": 1}}]))
            if sample:
                return {
                    "quote": sample[0].get("quote", DEFAULT_QUOTES[0]["quote"]),
                    "author": sample[0].get("author", DEFAULT_QUOTES[0]["author"]),
                }
        except Exception:
            pass
    chosen = random.choice(DEFAULT_QUOTES)
    return {"quote": chosen["quote"], "author": chosen["author"]}


def get_or_create_daily_quote(database: Database, user_id: str, date: str) -> dict:
    """
    24-Hour Cache Algorithm:
    1. Check MongoDB daily_quotes for this (user_id, date).
    2. If found, return cached quote (0 API calls).
    3. If not found, attempt RapidAPI call.
    4. If RapidAPI succeeds, store in DB for 24h and return.
    5. If RapidAPI fails/times out, pick random quote from default_quotes pool,
       store in DB for 24h, and return.
    """
    quotes_col = database["daily_quotes"]

    # 1. Check DB cache for this date
    try:
        cached = quotes_col.find_one({"user_id": user_id, "date": date})
        if cached and cached.get("quote"):
            return {
                "quote": cached["quote"],
                "author": cached.get("author", "Unknown"),
                "source": cached.get("source", "cached"),
            }
    except Exception as e:
        logger.warning(f"Error querying daily_quotes: {e}")

    # 2. Try RapidAPI
    quote_data = fetch_quote_from_rapidapi()
    source = "rapidapi"

    # 3. Fallback if RapidAPI failed
    if not quote_data:
        quote_data = get_random_fallback_quote(database)
        source = "fallback"

    # 4. Save to DB for this date (24-hour persistence)
    now = datetime.now(timezone.utc)
    try:
        quotes_col.update_one(
            {"user_id": user_id, "date": date},
            {
                "$set": {
                    "quote": quote_data["quote"],
                    "author": quote_data["author"],
                    "source": source,
                    "updated_at": now,
                },
                "$setOnInsert": {
                    "user_id": user_id,
                    "date": date,
                    "created_at": now,
                },
            },
            upsert=True,
        )
    except Exception as e:
        logger.warning(f"Could not persist daily quote: {e}")

    return {
        "quote": quote_data["quote"],
        "author": quote_data["author"],
        "source": source,
    }
