import os
import asyncio
import logging
from pymongo import AsyncMongoClient
from core.state import state

logger = logging.getLogger(__name__)

async def mongodb_reconnect_loop():
    """Background task to attempt MongoDB reconnection if disconnected."""
    while True:
        if state.users_collection is None:
            mongo_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
            mongo_db_name = os.getenv("MONGODB_DB", "afs")
            try:
                logger.info("Attempting to reconnect to MongoDB...")
                client = AsyncMongoClient(
                    mongo_uri, serverSelectionTimeoutMS=5000)
                # Ping to force connection verification
                await client.admin.command('ping')

                # Re-initialize state attributes
                state.mongo_client = client
                db = client[mongo_db_name]
                state.users_collection = db["users"]
                state.audio_recordings_collection = db["audio_recordings"]
                state.audio_settings_collection = db["audio_settings"]
                state.audio_angles_collection = db["audio_angles"]

                await state.users_collection.create_index("email", unique=True)
                logger.info("Successfully reconnected to MongoDB.")
            except Exception as e:
                logger.error(f"MongoDB reconnection failed: {e}")
                state.mongo_client = None
                state.users_collection = None
                state.audio_recordings_collection = None
                state.audio_settings_collection = None
                state.audio_angles_collection = None

        # Wait before next check (e.g., 10 seconds)
        await asyncio.sleep(10)

async def connect_db():
    mongo_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
    mongo_db_name = os.getenv("MONGODB_DB", "afs")

    try:
        client = AsyncMongoClient(
            mongo_uri, serverSelectionTimeoutMS=5000)
        # Ping to force connection verification
        await client.admin.command('ping')

        state.mongo_client = client
        db = client[mongo_db_name]
        state.users_collection = db["users"]
        state.audio_recordings_collection = db["audio_recordings"]
        state.audio_settings_collection = db["audio_settings"]
        state.audio_angles_collection = db["audio_angles"]

        await state.users_collection.create_index("email", unique=True)
        logger.info("Connected to MongoDB and initialized collections.")
    except Exception as e:
        logger.warning(f"MongoDB connection failed on startup: {e}. Starting reconnection loop.")
        state.mongo_client = None
        state.users_collection = None
        state.audio_recordings_collection = None
        state.audio_settings_collection = None
        state.audio_angles_collection = None

    asyncio.create_task(mongodb_reconnect_loop())

async def close_db():
    if state.mongo_client is not None:
        state.mongo_client.close()
        logger.info("MongoDB connection closed.")
