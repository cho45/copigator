@echo off

REM Check if PowerShell 7 is installed
where pwsh >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: PowerShell 7 not found.
    echo.
    echo Please install PowerShell 7 from:
    echo https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows
    echo.
    pause
    exit /b 1
)

REM Execute the script
pwsh -ExecutionPolicy Bypass -File "%~dp0copigator.ps1" %*

REM Check error code
if errorlevel 1 (
    echo.
    echo ERROR: An error occurred during execution.
    echo Please check the messages above.
    echo.
    pause
    exit /b 1
)

echo.
echo Process completed successfully.
pause
