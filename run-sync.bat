@echo off
setlocal enabledelayedexpansion
title Wiom Wallet Dashboard - Data Sync

echo.
echo  =========================================
echo   Wiom Wallet Dashboard - Data Sync Tool
echo  =========================================
echo.

set SCRIPT_URL=https://raw.githubusercontent.com/vipinchauhan-coder/wiom-wallet-dashboard/main/push-to-github.js
set SCRIPT_FILE=%~dp0push-to-github.js
set NODE_INSTALLER=%TEMP%\node-installer.msi
set NODE_URL=https://nodejs.org/dist/v20.18.0/node-v20.18.0-x64.msi

where node >nul 2>&1
if %errorlevel% == 0 (
    for /f "tokens=*" %%v in ('node --version 2^>nul') do set NODE_VER=%%v
        echo  [OK] Node.js found: !NODE_VER!
            goto :download_script
            )

            echo  [..] Node.js not found. Downloading installer...
            powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%NODE_URL%' -OutFile '%NODE_INSTALLER%' -UseBasicParsing }"

            if not exist "%NODE_INSTALLER%" (
                echo  [ERROR] Could not download Node.js. Install from https://nodejs.org then re-run.
                    pause
                        exit /b 1
                        )

                        echo  [..] Installing Node.js silently...
                        msiexec /i "%NODE_INSTALLER%" /quiet /norestart
                        set "PATH=%ProgramFiles%\nodejs;%APPDATA%\npm;%PATH%"

                        where node >nul 2>&1
                        if %errorlevel% neq 0 (
                            echo  [WARN] Node installed. Please CLOSE and RE-RUN this file.
                                pause
                                    exit /b 0
                                    )
                                    echo  [OK] Node.js installed!

                                    :download_script
                                    echo  [..] Downloading sync script...
                                    powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%SCRIPT_FILE%' -UseBasicParsing }"

                                    if not exist "%SCRIPT_FILE%" (
                                        echo  [ERROR] Could not download push-to-github.js
                                            pause
                                                exit /b 1
                                                )

                                                echo  [OK] Running sync...
                                                echo.
                                                node "%SCRIPT_FILE%"

                                                echo.
                                                if %errorlevel% == 0 (
                                                    echo  [OK] Done! https://vipinchauhan-coder.github.io/wiom-wallet-dashboard/
                                                    ) else (
                                                        echo  [ERROR] Sync failed - ensure this PC is on Wiom network/VPN.
                                                        )
                                                        echo.
                                                        pause
