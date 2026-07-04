@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem =====================================================================
rem START_WINDOWS.bat -- med-usb launcher for Windows 10/11 x64.
rem No installation, no admin rights. auditgw.exe is the process
rem supervisor (--spawn-llm): it launches and babysits llama-server.exe,
rem so this script stays trivial: read config, warn on low RAM, pick
rem free ports, start auditgw, wait for health, open the browser.
rem Servers bind 127.0.0.1 only. All paths relative to the stick root.
rem =====================================================================
cd /d "%~dp0"

echo =================================================
echo  med-usb : offline medical documentation copilot
echo =================================================

if not exist "stick.config" (
  echo ERROR: stick.config not found next to this launcher.
  goto fail
)
if not exist "bin\win-x64\auditgw.exe" (
  echo ERROR: bin\win-x64\auditgw.exe is missing.
  goto fail
)
if not exist "bin\win-x64\llama-server.exe" (
  echo ERROR: bin\win-x64\llama-server.exe is missing.
  goto fail
)

rem --- read stick.config: key=value, lines starting with # are comments ---
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("stick.config") do set "CFG_%%A=%%B"
if not defined CFG_ctx set "CFG_ctx=8192"
if not defined CFG_threads set "CFG_threads=auto"
if not defined CFG_llm_port_range set "CFG_llm_port_range=8080-8099"
if not defined CFG_ui_port_range set "CFG_ui_port_range=8180-8199"
if not defined CFG_build_id set "CFG_build_id=med-usb"

rem --- RAM check: warn below 8 GB, do not block ------------------------
set "RAM_GB="
for /f %%M in ('powershell -NoProfile -Command "[int][math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)" 2^>nul') do set "RAM_GB=%%M"
if defined RAM_GB (
  if !RAM_GB! LSS 8 (
    echo WARNING: this PC reports !RAM_GB! GB of RAM ^(less than 8 GB^).
    echo          The model may run very slowly or fail to load.
  )
) else (
  echo NOTE: could not determine RAM size, continuing anyway.
)

rem --- threads: auto = logical processor count -------------------------
set "THREADS=%CFG_threads%"
if /i "%THREADS%"=="auto" set "THREADS=%NUMBER_OF_PROCESSORS%"

rem --- pick the model: default first, then fallback --------------------
set "MODEL="
if defined CFG_default_model if exist "models\%CFG_default_model%" set "MODEL=%CFG_default_model%"
if not defined MODEL if defined CFG_fallback_model if exist "models\%CFG_fallback_model%" (
  echo NOTE: default model not found, using fallback model.
  set "MODEL=%CFG_fallback_model%"
)
if not defined MODEL (
  echo ERROR: no model file found in models\
  echo        expected: %CFG_default_model% or %CFG_fallback_model%
  goto fail
)
set "MODEL_SHA="
if exist "models\%MODEL%.sha256" for /f "usebackq" %%S in ("models\%MODEL%.sha256") do if not defined MODEL_SHA set "MODEL_SHA=%%S"

rem --- free-port scan in the configured ranges (netstat, no admin) -----
for /f "tokens=1,2 delims=-" %%A in ("%CFG_llm_port_range%") do (set "LLM_LO=%%A" & set "LLM_HI=%%B")
for /f "tokens=1,2 delims=-" %%A in ("%CFG_ui_port_range%") do (set "UI_LO=%%A" & set "UI_HI=%%B")

set "LLM_PORT="
for /l %%P in (%LLM_LO%,1,%LLM_HI%) do (
  if not defined LLM_PORT (
    netstat -an | findstr /i "LISTENING" | findstr /c:":%%P " >nul 2>&1
    if errorlevel 1 set "LLM_PORT=%%P"
  )
)
set "UI_PORT="
for /l %%P in (%UI_LO%,1,%UI_HI%) do (
  if not defined UI_PORT (
    netstat -an | findstr /i "LISTENING" | findstr /c:":%%P " >nul 2>&1
    if errorlevel 1 set "UI_PORT=%%P"
  )
)
if not defined LLM_PORT (
  echo ERROR: no free port in llm_port_range %CFG_llm_port_range%.
  goto fail
)
if not defined UI_PORT (
  echo ERROR: no free port in ui_port_range %CFG_ui_port_range%.
  goto fail
)

rem --- start auditgw; it spawns and supervises llama-server ------------
set "LLM_ARGS=--model models/%MODEL% --host 127.0.0.1 --port %LLM_PORT% --ctx-size %CFG_ctx% --threads %THREADS%"
if /i "%CFG_no_mmap%"=="true" set "LLM_ARGS=%LLM_ARGS% --no-mmap"
set "SHA_ARGS="
if defined MODEL_SHA set "SHA_ARGS=--model-sha256 %MODEL_SHA%"

echo starting auditgw ^(UI http://127.0.0.1:%UI_PORT%/ , llm port %LLM_PORT% , model %MODEL% , %THREADS% threads^)
start "med-usb auditgw (keep open while working)" /min "bin\win-x64\auditgw.exe" serve --spawn-llm --llm-bin bin/win-x64/llama-server.exe --llm-args "%LLM_ARGS%" --ui-dir ui --ui-port %UI_PORT% --llm-port %LLM_PORT% --audit-dir audit --model-file %MODEL% %SHA_ARGS% --build-id %CFG_build_id%

if not exist "audit" mkdir "audit" >nul 2>&1
(
  echo ui_port=%UI_PORT%
  echo llm_port=%LLM_PORT%
  echo model=%MODEL%
) > "audit\session-win.txt"

rem --- wait for health, then open the browser --------------------------
where curl.exe >nul 2>&1
if errorlevel 1 (
  echo NOTE: curl.exe not found, skipping health checks. Waiting 30 seconds.
  ping -n 31 127.0.0.1 >nul
  goto open_ui
)

echo waiting for the gateway to come up ...
set /a TRIES=0
:wait_gateway
curl.exe -s -o nul --max-time 2 "http://127.0.0.1:%UI_PORT%/api/status" >nul 2>&1
if not errorlevel 1 goto gateway_up
set /a TRIES+=1
if %TRIES% GEQ 60 (
  echo ERROR: gateway not answering on port %UI_PORT% after 60 seconds.
  echo        Check the minimized "med-usb auditgw" window for errors.
  goto fail
)
ping -n 2 127.0.0.1 >nul
goto wait_gateway

:gateway_up
echo gateway is up. waiting for the model to load ^(large models can take minutes^) ...
set /a TRIES=0
:wait_model
curl.exe -s --max-time 2 "http://127.0.0.1:%UI_PORT%/api/status" 2>nul | findstr /r /c:"llm_reachable.:true" >nul 2>&1
if not errorlevel 1 goto model_up
set /a TRIES+=1
if %TRIES% GEQ 300 (
  echo WARNING: model still loading after 5 minutes, opening the UI anyway.
  goto open_ui
)
ping -n 2 127.0.0.1 >nul
goto wait_model

:model_up
echo model is ready.

:open_ui
start "" "http://127.0.0.1:%UI_PORT%/"
echo.
echo med-usb is running:  http://127.0.0.1:%UI_PORT%/
echo The minimized "med-usb auditgw" window must stay open while you work.
echo To stop: run STOP_WINDOWS.bat
echo.
echo You can close THIS window now.
pause
exit /b 0

:fail
echo.
echo Launch failed. Press any key to close.
pause >nul
exit /b 1
