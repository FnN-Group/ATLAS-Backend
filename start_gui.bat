@echo off
setlocal
cd /d "%~dp0atlas_gui_flutter"

REM Check if Flutter is in PATH
where flutter >nul 2>&1
if %errorlevel% equ 0 (
    flutter run -d windows
) else (
    echo Error: Flutter SDK not found in PATH
    echo Please install Flutter and add it to your system PATH
    echo Visit: https://docs.flutter.dev/get-started/install/windows
    pause
)

endlocal
