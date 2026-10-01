import os
from pathlib import Path

from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.server_api import ServerApi


USERS = [
    {
        "user_id": "zen0001",
        "username": "prajwal",
        "name": "Prajwal",
        "phone_number": "9110687983",
        "goal": "muscle_gain",
        "body_weight_kg": 54.0,
        "daily_protein_target_g": 100.0,
        "daily_calorie_target": 2000.0,
        "daily_water_target_ml": 3000,
        "weekly_workout_target": 3,
    },
    {
        "user_id": "zen0002",
        "username": "viyola",
        "name": "Viyola Hezel Dsouza",
        "phone_number": "7619508647",
        "goal": "muscle_gain",
        "body_weight_kg": 50.0,
        "daily_protein_target_g": 100.0,
        "daily_calorie_target": 1800.0,
        "daily_water_target_ml": 2500,
        "weekly_workout_target": 3,
    },
]


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

        for u in USERS:
            existing = users.find_one({"$or": [{"user_id": u["user_id"]}, {"username": u["username"]}]})
            if existing:
                users.update_one({"_id": existing["_id"]}, {"$set": u, "$unset": {"phone": ""}})
                print(f"Updated predefined user {u['username']} ({u['user_id']}).")
            else:
                users.insert_one(u)
                print(f"Seeded predefined user {u['username']} ({u['user_id']}).")
    finally:
        client.close()


if __name__ == "__main__":
    main()