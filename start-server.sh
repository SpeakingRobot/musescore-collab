#!/bin/bash
# MuseCollab — Mac/Linux server startup script
# Run this from the musescore-collab/ directory

set -e

SERVER_DIR="$(cd "$(dirname "$0")/server" && pwd)"

echo "🎵 MuseCollab Server Setup"
echo "=========================="

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Install it from https://nodejs.org"
    echo "   Or via Homebrew: brew install node"
    exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "❌ Node.js 18+ required. You have: $(node -v)"
    echo "   Update via Homebrew: brew upgrade node"
    exit 1
fi

echo "✅ Node.js $(node -v) found"

cd "$SERVER_DIR"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Copy .env if missing
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo "📝 Created .env from .env.example"
        echo "   ⚠️  Please edit .env and set a strong JWT_SECRET before going public!"
    fi
fi

echo ""
echo "🚀 Starting MuseCollab server on http://localhost:3001"
echo "   Press Ctrl+C to stop"
echo ""

npm start
