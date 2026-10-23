@echo off
:: MuseCollab — Windows server startup script
:: Run this from the musescore-collab\ directory

echo 🎵 MuseCollab Server Setup
echo ==========================

:: Check Node.js
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo ❌ Node.js not found. Install from https://nodejs.org
    pause
    exit /b 1
)

echo ✅ Node.js found

cd /d "%~dp0server"

:: Install dependencies if needed
if not exist "node_modules" (
    echo 📦 Installing dependencies...
    npm install
)

:: Copy .env if missing
if not exist ".env" (
    if exist ".env.example" (
        copy ".env.example" ".env"
        echo 📝 Created .env from .env.example
    )
)

echo.
echo 🚀 Starting MuseCollab server on http://localhost:3001
echo    Press Ctrl+C to stop
echo.

npm start
