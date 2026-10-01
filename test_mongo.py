import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.server_api import ServerApi


USER_ID = "zen0001"
USERNAME = "prajwal"
USER_PHONE = "9110687983"


def main():
    load_dotenv(Path(__file__).resolve().parent / "backend" / ".env")
    uri = os.getenv("MONGODB_URI") or os.getenv("MONGO_URI")
    if not uri:
        print("Set MONGODB_URI or MONGO_URI in the environment or .env file.")
        return 1

    client = MongoClient(uri, server_api=ServerApi("1"), serverSelectionTimeoutMS=5000)
    try:
        client.admin.command("ping")
        print("Pinged your deployment. Successfully connected to MongoDB.")

        users = client[os.getenv("MONGODB_DATABASE", "zenlog")]["users"]
        user = users.find_one(
            {
                "user_id": USER_ID,
                "username": USERNAME,
                "phone_number": USER_PHONE,
            },
            {"_id": 0, "phone_number": 0},
        )
        if user:
            print("Verified seeded user prajwal (zen0001).")
            return 0

        print("Seeded user verification failed: expected record was not found.")
        return 1
    except Exception as error:
        print(f"MongoDB check failed: {error}")
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())