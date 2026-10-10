import getpass
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Add project root to sys.path
_root = str(Path(__file__).resolve().parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

from dotenv import load_dotenv
from pymongo import MongoClient

from backend.core.security import hash_pin


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/set_pin.py <username> [pin]")
        sys.exit(1)

    username = sys.argv[1].strip().lower()

    if len(sys.argv) >= 3:
        pin = sys.argv[2].strip()
    else:
        pin = getpass.getpass(f"Enter 4-8 digit PIN for '{username}': ").strip()
        confirm = getpass.getpass("Confirm PIN: ").strip()
        if pin != confirm:
            print("Error: PINs do not match.")
            sys.exit(1)

    try:
        hashed = hash_pin(pin)
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

    # Load environment variables
    env_path = Path(_root) / "backend" / ".env"
    if not env_path.exists():
        env_path = Path(_root) / ".env"
    load_dotenv(env_path)

    mongo_uri = os.getenv("MONGODB_URI") or os.getenv("MONGO_URI")
    if not mongo_uri:
        print("Error: MONGODB_URI not set in environment or .env file.")
        sys.exit(1)

    client = MongoClient(mongo_uri)
    db_name = os.getenv("MONGODB_DATABASE", "zenlog")
    db = client[db_name]

    user = db["users"].find_one({"username": username})
    if not user:
        print(f"Error: User '{username}' not found in database '{db_name}'.")
        sys.exit(1)

    db["users"].update_one(
        {"username": username},
        {"$set": {
            "pin_hash": hashed,
            "pin_updated_at": datetime.now(timezone.utc),
        }},
    )

    print(f"Successfully set PIN for user '{username}'.")


if __name__ == "__main__":
    main()
