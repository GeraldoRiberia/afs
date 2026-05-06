#!/bin/bash

# Function to clean up background processes on exit
cleanup() {
    echo "Stopping all services..."
    # Kill all child processes of this script
    pkill -P $$
    exit
}

# Trap SIGINT (Ctrl+C) and SIGTERM to run the cleanup function
trap cleanup SIGINT SIGTERM

# Activating the conda environment
eval "$(conda shell.bash hook)"
conda activate afs_env

# Start the Backend server in the background
echo "Starting Backend (Port 8000)..."
(cd backend && python server.py) &

# Start the FastAPI microservice in the background
echo "Starting FastAPI Microservice (Port 8001)..."
(cd Model && python fastapi_app.py) &

# Start the Flutter frontend in the foreground so you can use hot-reload
echo "Starting Flutter Frontend..."
cd afs && flutter run -d macos
