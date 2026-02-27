@echo off
:: ============================================================================
:: winDOHs Update Disabler - BAT Edition 
:: Fully disables or re-enables Windows Update with a single click.
:: Must be run as Administrator.
:: ============================================================================
title winDOHs Update Disabler
color 0A

:: --- Check for Admin ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: This script must be run as Administrator.
    echo  Right-click the file and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

:MENU
cls
echo.
echo  ============================================================
echo       winDOHs Update Disabler  -  BAT Edition
echo  ============================================================
echo.
echo    [1] INSTALL  - Disable ^& Block ALL Windows Updates
echo    [2] REVERT   - Re-enable Windows Updates
echo    [3] EXIT
echo.
set /p choice="  Select an option (1/2/3): "

if "%choice%"=="1" goto INSTALL
if "%choice%"=="2" goto REVERT
if "%choice%"=="3" exit /b 0
goto MENU

:: ======================= INSTALL (DISABLE UPDATES) =========================
:INSTALL
cls
echo.
echo  ============================================================
echo   DISABLING ALL WINDOWS UPDATES...
echo  ============================================================
echo.

:: 1. Stop update-related services
echo  [1/8] Stopping Windows Update services...
net stop wuauserv        2>nul
net stop UsoSvc          2>nul
net stop WaaSMedicSvc    2>nul
net stop bits            2>nul
net stop dosvc           2>nul
net stop uhssvc          2>nul

:: 2. Disable update-related services (set to Disabled)
echo  [2/8] Disabling Windows Update services...
sc config wuauserv       start= disabled >nul 2>&1
sc config UsoSvc         start= disabled >nul 2>&1
sc config WaaSMedicSvc   start= disabled >nul 2>&1
sc config bits           start= disabled >nul 2>&1
sc config dosvc          start= disabled >nul 2>&1
sc config uhssvc         start= disabled >nul 2>&1

:: 3. Block restart/re-enable of WaaSMedicSvc via registry
echo  [3/8] Locking WaaSMedicSvc from self-healing...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start /t REG_DWORD /d 4 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1

:: 4. Group Policy: Disable Automatic Updates
echo  [4/8] Applying Group Policy registry keys...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DoNotConnectToWindowsUpdateInternetLocations /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWindowsUpdateAccess /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetDisableUXWUAccess /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ExcludeWUDriversInQualityUpdate /t REG_DWORD /d 1 /f >nul 2>&1

:: 5. Disable Windows Update Orchestrator scheduled tasks
echo  [5/8] Disabling Windows Update scheduled tasks...
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\Scheduled Start" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\sih" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\sihboot" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Work" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Wake To Work" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Report policies" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WaaSMedic\PerformRemediation" /Disable >nul 2>&1

:: 6. Block Windows Update domains via HOSTS file
echo  [6/8] Blocking Windows Update servers in HOSTS file...
set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
:: Add marker so we can cleanly revert later
findstr /c:"# winDOHs-UPDATE-BLOCK-START" "%HOSTS%" >nul 2>&1
if %errorlevel% neq 0 (
    echo.>> "%HOSTS%"
    echo # winDOHs-UPDATE-BLOCK-START>> "%HOSTS%"
    echo 0.0.0.0 windowsupdate.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 update.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 windowsupdate.com>> "%HOSTS%"
    echo 0.0.0.0 download.windowsupdate.com>> "%HOSTS%"
    echo 0.0.0.0 download.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 wustat.windows.com>> "%HOSTS%"
    echo 0.0.0.0 ntservicepack.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 go.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 dl.delivery.mp.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 sls.update.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 fe2.update.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 fe3.delivery.mp.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 tsfe.trafficshaping.dsp.mp.microsoft.com>> "%HOSTS%"
    echo 0.0.0.0 emdl.ws.microsoft.com>> "%HOSTS%"
    echo # winDOHs-UPDATE-BLOCK-END>> "%HOSTS%"
)

:: 7. Rename the Windows Update directory to prevent cached updates
echo  [7/8] Renaming SoftwareDistribution folder...
ren "%SystemRoot%\SoftwareDistribution" SoftwareDistribution.bak >nul 2>&1

:: 8. Block Windows Update exe with Windows Firewall
echo  [8/8] Adding firewall rules to block update binaries...
netsh advfirewall firewall add rule name="winDOHs Block wuauclt" dir=out action=block program="%SystemRoot%\System32\wuauclt.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block WaaSMedic" dir=out action=block program="%SystemRoot%\System32\WaaSMedicAgent.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block UsoClient" dir=out action=block program="%SystemRoot%\System32\UsoClient.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block musNotify" dir=out action=block program="%SystemRoot%\System32\musNotification.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block musNotifyWorker" dir=out action=block program="%SystemRoot%\System32\musNotificationUx.exe" enable=yes >nul 2>&1

echo.
echo  ============================================================
echo   ALL DONE - Windows Update has been DISABLED.
echo   A reboot is recommended to fully apply changes.
echo  ============================================================
echo.
pause
goto MENU

:: ======================== REVERT (RE-ENABLE UPDATES) ========================
:REVERT
cls
echo.
echo  ============================================================
echo   RE-ENABLING WINDOWS UPDATES...
echo  ============================================================
echo.

:: 1. Re-enable services
echo  [1/8] Re-enabling Windows Update services...
sc config wuauserv       start= demand >nul 2>&1
sc config UsoSvc         start= demand >nul 2>&1
sc config WaaSMedicSvc   start= demand >nul 2>&1
sc config bits           start= delayed-auto >nul 2>&1
sc config dosvc          start= delayed-auto >nul 2>&1
sc config uhssvc         start= demand >nul 2>&1

:: 2. Start services
echo  [2/8] Starting Windows Update services...
net start bits           2>nul
net start wuauserv       2>nul
net start UsoSvc         2>nul
net start dosvc          2>nul

:: 3. Remove WaaSMedicSvc locks
echo  [3/8] Restoring WaaSMedicSvc defaults...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start /t REG_DWORD /d 3 /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v FailureActions /f >nul 2>&1

:: 4. Remove Group Policy keys
echo  [4/8] Removing Group Policy registry keys...
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DoNotConnectToWindowsUpdateInternetLocations /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWindowsUpdateAccess /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetDisableUXWUAccess /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ExcludeWUDriversInQualityUpdate /f >nul 2>&1

:: 5. Re-enable scheduled tasks
echo  [5/8] Re-enabling Windows Update scheduled tasks...
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\Scheduled Start" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\sih" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\sihboot" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Work" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Wake To Work" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Report policies" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WaaSMedic\PerformRemediation" /Enable >nul 2>&1

:: 6. Remove HOSTS file blocks
echo  [6/8] Removing HOSTS file blocks...
set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
set "TEMP_HOSTS=%TEMP%\hosts_clean.tmp"
if exist "%TEMP_HOSTS%" del /f "%TEMP_HOSTS%"
setlocal enabledelayedexpansion
set "SKIP=0"
for /f "usebackq delims=" %%L in ("%HOSTS%") do (
    set "LINE=%%L"
    if "!LINE!"=="# winDOHs-UPDATE-BLOCK-START" (
        set "SKIP=1"
    )
    if "!SKIP!"=="0" (
        echo !LINE!>> "%TEMP_HOSTS%"
    )
    if "!LINE!"=="# winDOHs-UPDATE-BLOCK-END" (
        set "SKIP=0"
    )
)
endlocal
copy /y "%TEMP_HOSTS%" "%HOSTS%" >nul 2>&1
del /f "%TEMP_HOSTS%" >nul 2>&1

:: 7. Restore SoftwareDistribution folder
echo  [7/8] Restoring SoftwareDistribution folder...
ren "%SystemRoot%\SoftwareDistribution.bak" SoftwareDistribution >nul 2>&1

:: 8. Remove firewall rules
echo  [8/8] Removing firewall block rules...
netsh advfirewall firewall delete rule name="winDOHs Block wuauclt" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block WaaSMedic" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block UsoClient" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block musNotify" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block musNotifyWorker" >nul 2>&1

echo.
echo  ============================================================
echo   ALL DONE - Windows Update has been RE-ENABLED.
echo   A reboot is recommended to fully apply changes.
echo  ============================================================
echo.
pause
goto MENU
