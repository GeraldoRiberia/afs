#!/usr/bin/env python3
"""Test user registration and session creation in MongoDB."""
import asyncio
import os
from pymongo import AsyncMongoClient
from passlib.context import CryptContext
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

async def test_create_user():
    """Test creating a user in the database."""
    mongo_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
    mongo_db_name = os.getenv("MONGODB_DB", "afs")
    
    print(f"Testing user creation in MongoDB...")
    print(f"Database: {mongo_db_name}")
    
    try:
        # Connect
        print("\n1. Connecting to MongoDB...")
        client = AsyncMongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
        db = client[mongo_db_name]
        users_collection = db["users"]
        
        # Create index
        print("2. Creating email index...")
        await users_collection.create_index("email", unique=True)
        
        # Create test user
        test_email = "test@example.com"
        test_username = "testuser"
        test_password = "test123"  # Shorter password to avoid bcrypt issues
        
        print(f"\n3. Creating user '{test_username}'...")
        
        # Check if user exists
        existing = await users_collection.find_one({"email": test_email})
        if existing:
            print(f"⚠️  User already exists. Deleting old user...")
            await users_collection.delete_one({"email": test_email})
        
        # Hash password
        hashed_password = pwd_context.hash(test_password)
        
        # Insert user
        user_doc = {
            "email": test_email,
            "username": test_username,
            "hashed_password": hashed_password,
            "created_at": "2026-04-05T19:15:00Z"
        }
        
        result = await users_collection.insert_one(user_doc)
        print(f"✅ User created with ID: {result.inserted_id}")
        
        # Verify user
        print("\n4. Verifying user...")
        user = await users_collection.find_one({"email": test_email})
        print(f"✅ User found:")
        print(f"   Email: {user['email']}")
        print(f"   Username: {user['username']}")
        print(f"   ID: {user['_id']}")
        
        # Test password verification
        print("\n5. Testing password verification...")
        if pwd_context.verify(test_password, user['hashed_password']):
            print("✅ Password verified!")
        else:
            print("❌ Password verification failed!")
        
        # List all users
        print("\n6. Listing all users...")
        all_users = await users_collection.find().to_list(length=10)
        print(f"✅ Total users in database: {len(all_users)}")
        for u in all_users:
            print(f"   - {u['username']} ({u['email']})")
        
        print("\n✅ User creation test passed!")
        print(f"\nYou can now login with:")
        print(f"   Email: {test_email}")
        print(f"   Password: {test_password}")
        
        client.close()
        return True
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        print(f"Error type: {type(e).__name__}")
        return False

if __name__ == "__main__":
    success = asyncio.run(test_create_user())
    exit(0 if success else 1)
