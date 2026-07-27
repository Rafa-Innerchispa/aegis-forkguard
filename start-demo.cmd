@echo off
REM ===================================================================
REM  AEGIS ForkGuard - one-click demo launcher (Windows)
REM
REM  Double-click this file. It starts the Jac server and opens the
REM  dashboard at the correct URL.
REM
REM  Why this exists: opening assets\index.html directly from Explorer
REM  loads it over file://, where every request to /walker/... resolves
REM  against the file system and can never reach the engine. The page
REM  then correctly reports the backend as unreachable. This script
REM  always opens the served URL instead.
REM ===================================================================

setlocal
cd /d "%~dp0"

echo.
echo  AEGIS ForkGuard - starting...
echo.

REM Locate the jac executable: PATH first, then the usual per-user install.
where jac >nul 2>&1
if %errorlevel%==0 (
    set "JAC=jac"
) else if exist "%LOCALAPPDATA%\Programs\Python\Python312\Scripts\jac.exe" (
    set "JAC=%LOCALAPPDATA%\Programs\Python\Python312\Scripts\jac.exe"
) else (
    echo  [X] Could not find the 'jac' command.
    echo      Install it with:  pip install jaseci
    echo.
    pause
    exit /b 1
)

REM Is a *working* ForkGuard already on 8000? Probe a real walker, not
REM /healthz: a stray static file server also occupies the port and serves
REM pages happily while rejecting every POST, which looks exactly like
REM "backend offline" in the dashboard.
call :probe
if %errorlevel%==0 (
    echo  [i] A working ForkGuard server is already running on port 8000.
    goto :open
)

REM Port taken by something that is NOT ForkGuard - stop it, or we will
REM serve a dashboard that can never reach its engine.
netstat -ano ^| findstr /r /c:"LISTENING" ^| findstr ":8000 " >nul 2>&1
if %errorlevel%==0 (
    echo  [!] Port 8000 is held by a process that is not ForkGuard. Stopping it...
    powershell -NoProfile -Command ^
      "Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 8000 } | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"
    REM ping instead of timeout: timeout aborts when stdin is redirected.
    ping -n 4 127.0.0.1 >nul
)

echo  [1/2] Starting the Jac server...
start "ForkGuard server" /min cmd /c "%JAC% start main.jac"

echo  [2/2] Waiting for the walkers to answer...
powershell -NoProfile -Command ^
  "$d=(Get-Date).AddSeconds(180); while((Get-Date) -lt $d){ try{ $r=Invoke-WebRequest 'http://localhost:8000/walker/reset_demo_api' -Method POST -Body '{}' -ContentType 'application/json' -UseBasicParsing -TimeoutSec 10; if($r.StatusCode -eq 200){ exit 0 } }catch{}; Start-Sleep 3 }; exit 1"

if not %errorlevel%==0 (
    echo.
    echo  [X] The server did not come up within 180 seconds.
    echo      Run it manually to see the error:  jac start main.jac
    echo.
    pause
    exit /b 1
)

:open
echo.
echo  [OK] Dashboard: http://localhost:8000/static/index.html
echo.
start "" "http://localhost:8000/static/index.html"

echo  Leave the minimised "ForkGuard server" window open during the demo.
echo  Closing it stops the server.
echo.
ping -n 7 127.0.0.1 >nul
endlocal
exit /b 0

REM --- returns 0 only if a real ForkGuard walker answers on 8000 ---
:probe
powershell -NoProfile -Command ^
  "try{ $r=Invoke-WebRequest 'http://localhost:8000/walker/reset_demo_api' -Method POST -Body '{}' -ContentType 'application/json' -UseBasicParsing -TimeoutSec 8; if($r.StatusCode -eq 200){ exit 0 } else { exit 1 } }catch{ exit 1 }" >nul 2>&1
exit /b %errorlevel%
