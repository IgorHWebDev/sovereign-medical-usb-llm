@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem =====================================================================
rem STOP_WINDOWS.bat -- graceful shutdown of the med-usb stack.
rem Calls POST /api/shutdown via curl.exe (bundled with Windows 10 1803+);
rem auditgw then stops the llama-server it supervises. taskkill fallback
rem if anything is still alive. Appends a session-end audit event.
rem =====================================================================
cd /d "%~dp0"

set "UI_LO=8180"
set "UI_HI=8199"
if exist "stick.config" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("stick.config") do set "CFG_%%A=%%B"
if defined CFG_ui_port_range for /f "tokens=1,2 delims=-" %%A in ("%CFG_ui_port_range%") do (set "UI_LO=%%A" & set "UI_HI=%%B")

set "SESSION_PORT="
if exist "audit\session-win.txt" for /f "usebackq tokens=1,* delims==" %%A in ("audit\session-win.txt") do if /i "%%A"=="ui_port" set "SESSION_PORT=%%B"

set "FOUND="
where curl.exe >nul 2>&1
if errorlevel 1 (
  echo NOTE: curl.exe not found, falling back to taskkill.
  goto force_kill
)

if defined SESSION_PORT call :try_stop %SESSION_PORT%
if defined FOUND goto wait_exit
for /l %%P in (%UI_LO%,1,%UI_HI%) do if not defined FOUND call :try_stop %%P
goto wait_exit

:try_stop
rem only talk to services that identify themselves as auditgw
curl.exe -s --max-time 2 "http://127.0.0.1:%1/api/status" 2>nul | findstr /c:"auditgw" >nul 2>&1
if errorlevel 1 goto :eof
echo sending shutdown to auditgw on port %1 ...
curl.exe -s -o nul --max-time 3 -X POST "http://127.0.0.1:%1/api/shutdown" >nul 2>&1
set "FOUND=1"
goto :eof

:wait_exit
if not defined FOUND echo no running auditgw found on ports %UI_LO%-%UI_HI%.
ping -n 6 127.0.0.1 >nul
tasklist /fi "imagename eq auditgw.exe" 2>nul | findstr /i "auditgw.exe" >nul 2>&1
if errorlevel 1 goto append_end

:force_kill
echo auditgw still running, forcing termination ^(taskkill fallback^).
taskkill /f /im auditgw.exe >nul 2>&1
taskkill /f /im llama-server.exe >nul 2>&1

:append_end
rem session-end audit event (best effort, hash-chained by auditgw append)
set "YM="
for /f %%D in ('powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyyMM')" 2^>nul') do set "YM=%%D"
if defined YM if exist "bin\win-x64\auditgw.exe" (
  "bin\win-x64\auditgw.exe" append --file "audit/audit-%YM%.jsonl" --operator "launcher:win" --prompt "session-end" --response "session ended via STOP_WINDOWS.bat" >nul 2>&1
)

echo stop complete. You can close this window.
pause
exit /b 0
