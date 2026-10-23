@echo off
setlocal
title MuseCollab Plugin Installer

echo ================================================================
echo           🎵  MuseCollab 1-Click Plugin Installer
echo ================================================================
echo.

:: Check if Node is installed
where node >nul 2>nul
if %errorlevel% equ 0 (
    node "%~dp0install.js"
    goto finish
)

:: Pure Windows fallback (No Node required!)
echo Node.js not detected, using Windows built-in PowerShell installer...
echo.

set "TARGET_DIR=%USERPROFILE%\Documents\MuseScore4\Plugins\MuseCollab"

if not exist "%USERPROFILE%\Documents\MuseScore4\Plugins" (
    if exist "%USERPROFILE%\Documents\MuseScore3\Plugins" (
        set "TARGET_DIR=%USERPROFILE%\Documents\MuseScore3\Plugins\MuseCollab"
    )
)

echo Installing to: %TARGET_DIR%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Force '%TARGET_DIR%' | Out-Null; Copy-Item -Recurse '%~dp0plugin\*' '%TARGET_DIR%' -Force"

if %errorlevel% equ 0 (
    echo ================================================================
    echo        [OK] MuseCollab Plugin Installed Successfully!
    echo ================================================================
    echo.
    echo Installed to: %TARGET_DIR%
    echo Server: https://musescore-collab.onrender.com (Pre-configured!)
    echo.
    echo Next Steps:
    echo   1. Open MuseScore
    echo   2. Go to: Plugins -^> Manage Plugins
    echo   3. Check [X] MuseCollab
    echo   4. Open from top menu: Plugins -^> MuseCollab
    echo.
) else (
    echo [ERROR] Installation failed. Please run as Administrator or copy the plugin folder manually.
)

:finish
echo.
echo Press any key to exit...
pause >nul
