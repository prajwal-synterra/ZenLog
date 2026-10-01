import os
from pathlib import Path

from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.server_api import ServerApi


USER = {
    "user_id": "zen0001",
    "username": "prajwal",
    "name": "Prajwal",
    "phone_number": "9110687983",
}


def main() -> None:
    load_dotenv(Path(__file__).resolve().parent / ".env")
    mongo_uri = os.getenv("MONGODB_URI") or os.getenv("MONGO_URI")
    if not mongo_uri:
        raise RuntimeError("Set MONGODB_URI or MONGO_URI in the environment or .env file.")

    client = MongoClient(
        mongo_uri,
        server_api=ServerApi("1"),
        serverSelectionTimeoutMS=5000,
    )
    try:
        client.admin.command("ping")
        database = client[os.getenv("MONGODB_DATABASE", "zenlog")]
        users = database["users"]

        existing = users.find_one(
            {
                "$or": [
                    {"user_id": USER["user_id"]},
                    {"phone_number": USER["phone_number"]},
                    {"phone": USER["phone_number"]},
                ]
            }
        )
        username_owner = users.find_one({"username": USER["username"]})
        if username_owner and existing and username_owner["_id"] != existing["_id"]:
            raise RuntimeError("The requested username belongs to a different user record.")
        if username_owner and existing is None:
            raise RuntimeError("The requested username belongs to a different user record.")

        if existing:
            users.update_one(
                {"_id": existing["_id"]},
                {"$set": USER, "$unset": {"phone": ""}},
            )
            action = "Updated"
        else:
            users.insert_one(USER)
            action = "Seeded"

        print(f"{action} predefined user {USER['username']} ({USER['user_id']}).")
    finally:
        client.close()


if __name__ == "__main__":
    main()