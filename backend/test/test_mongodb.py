"""Test MongoDB connection to verify configuration"""
import os
import asyncio
from dotenv import load_dotenv
from pymongo import AsyncMongoClient

async def test_mongodb_connection():
    # Load environment variables
    load_dotenv()
    
    mongo_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
    mongo_db_name = os.getenv("MONGODB_DB", "afs")
    
    print(f"Testing MongoDB connection...")
    print(f"URI: {mongo_uri[:20]}... (truncated for security)")
    print(f"Database: {mongo_db_name}")
    
    try:
        client = AsyncMongoClient(mongo_uri)
        # Test the connection
        await client.admin.command('ping')
        print("✓ Successfully connected to MongoDB!")
        
        # Test database access
        db = client[mongo_db_name]
        collections = await db.list_collection_names()
        print(f"✓ Database '{mongo_db_name}' accessible")
        print(f"  Collections: {collections if collections else '(none)'}")
        
        client.close()
        print("✓ Connection closed successfully")
        return True
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return False

if __name__ == "__main__":
    asyncio.run(test_mongodb_connection())
