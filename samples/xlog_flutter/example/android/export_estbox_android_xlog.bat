@echo off
setlocal enabledelayedexpansion

chcp 65001 >nul

set PACKAGE_NAME=com.tencent.estbox
set REMOTE_DIR=/data/data/%PACKAGE_NAME%/files/xlog
set LOCAL_DIR=.\xlog_dump

echo.
echo ====== XLOG EXPORT TOOL ======
echo PACKAGE: %PACKAGE_NAME%
echo.

if not exist %LOCAL_DIR% (
mkdir %LOCAL_DIR%
)

adb get-state 1>nul 2>nul
if errorlevel 1 (
echo [ERROR] No device detected
pause
exit /b
)

echo [INFO] Device detected
echo.

echo [STEP 1] Trying run-as with direct pipe...

adb exec-out run-as %PACKAGE_NAME% ls files/xlog 1>nul 2>nul
if %errorlevel%==0 (
echo [OK] run-as available

echo [INFO] Exporting logs directly via tar pipe...
adb exec-out run-as %PACKAGE_NAME% sh -c "cd files && tar -czf - xlog" > %LOCAL_DIR%\xlog.tar.gz 2>nul
if %errorlevel%==0 (
    echo [SUCCESS] Logs exported via run-as
    echo [INFO] Extracting to %LOCAL_DIR%...
    cd /d %LOCAL_DIR%
    tar -xzf xlog.tar.gz
    del xlog.tar.gz
    cd /d %~dp0
    goto :end
) else (
    echo [ERROR] Failed to export logs via pipe
    del %LOCAL_DIR%\xlog.tar.gz 2>nul
)

)

echo [WARN] run-as not available or failed
echo.

echo [STEP 2] Trying root...

adb root 1>nul 2>nul
timeout /t 2 >nul

adb pull %REMOTE_DIR% %LOCAL_DIR% 1>nul 2>nul
if %errorlevel%==0 (
echo [SUCCESS] Root export success
goto :end
)

echo [WARN] root not available
echo.

echo [STEP 3] Trying /data/local/tmp direct pull...

adb pull /data/local/tmp/xlog %LOCAL_DIR% 1>nul 2>nul
if %errorlevel%==0 (
echo [SUCCESS] Found at /data/local/tmp/xlog
goto :end
)

adb pull /sdcard/Android/data/%PACKAGE_NAME%/files/xlog %LOCAL_DIR% 1>nul 2>nul
if %errorlevel%==0 (
echo [SUCCESS] Found at Android/data path
goto :end
)

echo.
echo [FAILED] All methods failed
echo.

:end
echo.
echo ====== DONE ======
pause
