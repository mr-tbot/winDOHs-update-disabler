@echo off
:: ============================================================================
:: winDOHs Update Disabler - BAT Edition (v2)
:: Fully disables or re-enables Windows Update with a single click.
:: Must be run as Administrator.
:: v2 - Enhanced with 12 layers including ACL lockdown and expanded coverage.
:: ============================================================================
title winDOHs Update Disabler (v2)
color 0A

:: --- Check for Admin, self-elevate via UAC if needed ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  Requesting administrator access...
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList '/c \"\"%~f0\"\"'"
    exit /b 0
)

:MENU
cls
echo.
echo  ============================================================
echo       winDOHs Update Disabler  -  BAT Edition (v2)
echo  ============================================================
echo.
echo    [1] INSTALL  - Disable ^& Block ALL Windows Updates
echo    [2] REVERT   - Re-enable Windows Updates
echo    [3] STATUS   - Check current block status
echo    [4] EXIT
echo.
set /p choice="  Select an option (1/2/3/4): "

if "%choice%"=="1" goto INSTALL
if "%choice%"=="2" goto REVERT
if "%choice%"=="3" goto STATUS
if "%choice%"=="4" exit /b 0
goto MENU

:: ======================= INSTALL (DISABLE UPDATES) =========================
:INSTALL
cls
echo.
echo  ============================================================
echo   DISABLING ALL WINDOWS UPDATES (v2 - 12 layers)...
echo  ============================================================
echo.

:: 1. Stop update-related services
echo  [1/12] Stopping Windows Update services...
net stop wuauserv        2>nul
net stop UsoSvc          2>nul
net stop WaaSMedicSvc    2>nul
net stop bits            2>nul
net stop dosvc           2>nul
net stop uhssvc          2>nul
net stop sedsvc          2>nul

:: 2. Disable update-related services + null failure/recovery actions for ALL
echo  [2/12] Disabling services ^& nullifying recovery actions...
sc config wuauserv       start= disabled >nul 2>&1
sc config UsoSvc         start= disabled >nul 2>&1
sc config WaaSMedicSvc   start= disabled >nul 2>&1
sc config bits           start= disabled >nul 2>&1
sc config dosvc          start= disabled >nul 2>&1
sc config uhssvc         start= disabled >nul 2>&1
sc config sedsvc         start= disabled >nul 2>&1
:: Null failure actions for ALL services (not just WaaSMedic like v1)
reg add "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\bits" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\dosvc" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\uhssvc" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\sedsvc" /v FailureActions /t REG_BINARY /d 00000000000000000000000003000000140000000000000060ea00000000000060ea00000000000060ea0000 /f >nul 2>&1

:: 3. Lock service registry keys (anti-tamper) — prevents WaaSMedic self-healing
::    This uses PowerShell to set DENY ACLs on SYSTEM for the registry keys,
::    which is the #1 reason Windows can bypass service disabling.
echo  [3/12] Locking service registry keys (anti-tamper)...
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "foreach($svc in @('wuauserv','UsoSvc','WaaSMedicSvc')){try{$p='SYSTEM\CurrentControlSet\Services\'+$svc;$k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($p,'ReadWriteSubTree',[System.Security.AccessControl.RegistryRights]::TakeOwnership);if(-not $k){continue};$a=$k.GetAccessControl();$admin=[System.Security.Principal.NTAccount]'BUILTIN\Administrators';$a.SetOwner($admin);$k.SetAccessControl($a);$k.Close();$k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($p,'ReadWriteSubTree',([System.Security.AccessControl.RegistryRights]::ChangePermissions-bor[System.Security.AccessControl.RegistryRights]::ReadKey));$a=$k.GetAccessControl();$a.SetAccessRuleProtection($true,$false);foreach($r in $a.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])){$a.RemoveAccessRuleSpecific($r)};$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($admin,'FullControl','ContainerInherit,ObjectInherit','None','Allow')));$sys=[System.Security.Principal.NTAccount]'NT AUTHORITY\SYSTEM';$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($sys,'ReadKey','ContainerInherit,ObjectInherit','None','Allow')));$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($sys,'SetValue,CreateSubKey,Delete','ContainerInherit,ObjectInherit','None','Deny')));$k.SetAccessControl($a);$k.Close()}catch{}}" >nul 2>&1

:: 4. Group Policy: Disable Automatic Updates (expanded)
echo  [4/12] Applying Group Policy registry keys...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DoNotConnectToWindowsUpdateInternetLocations /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWindowsUpdateAccess /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetDisableUXWUAccess /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ExcludeWUDriversInQualityUpdate /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetPolicyDrivenUpdateSourceForFeatureUpdates /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetPolicyDrivenUpdateSourceForQualityUpdates /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableOSUpgrade /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuildsPolicyValue /t REG_DWORD /d 1 /f >nul 2>&1

:: 5. Additional registry hardening (maintenance, store, version lock)
echo  [5/12] Applying additional registry hardening...
:: Disable automatic maintenance (triggers update scans)
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" /v MaintenanceDisabled /t REG_DWORD /d 1 /f >nul 2>&1
:: Disable Windows Store auto-updates
reg add "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload /t REG_DWORD /d 2 /f >nul 2>&1
:: Disable OS upgrade via another codepath
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade" /v AllowOSUpgrade /t REG_DWORD /d 0 /f >nul 2>&1
:: Lock to current OS version (prevent feature updates)
set "CURVER="
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2^>nul ^| findstr /i "DisplayVersion"') do set "CURVER=%%a"
if not defined CURVER (
    for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ReleaseId 2^>nul ^| findstr /i "ReleaseId"') do set "CURVER=%%a"
)
if defined CURVER (
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersion /t REG_DWORD /d 1 /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersionInfo /t REG_SZ /d "%CURVER%" /f >nul 2>&1
    echo          Locked to OS version: %CURVER%
)
:: Lock GP registry keys with ACLs to prevent SYSTEM from reverting them
echo          Locking Group Policy keys against SYSTEM writes...
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "foreach($p in @('SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU','SOFTWARE\Policies\Microsoft\WindowsStore')){try{$k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($p,'ReadWriteSubTree',[System.Security.AccessControl.RegistryRights]::TakeOwnership);if(-not $k){continue};$a=$k.GetAccessControl();$admin=[System.Security.Principal.NTAccount]'BUILTIN\Administrators';$a.SetOwner($admin);$k.SetAccessControl($a);$k.Close();$k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($p,'ReadWriteSubTree',([System.Security.AccessControl.RegistryRights]::ChangePermissions-bor[System.Security.AccessControl.RegistryRights]::ReadKey));$a=$k.GetAccessControl();$a.SetAccessRuleProtection($true,$false);foreach($r in $a.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])){$a.RemoveAccessRuleSpecific($r)};$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($admin,'FullControl','ContainerInherit,ObjectInherit','None','Allow')));$sys=[System.Security.Principal.NTAccount]'NT AUTHORITY\SYSTEM';$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($sys,'ReadKey','ContainerInherit,ObjectInherit','None','Allow')));$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($sys,'SetValue,CreateSubKey,Delete','ContainerInherit,ObjectInherit','None','Deny')));$k.SetAccessControl($a);$k.Close()}catch{}}"

:: 6. Disable Windows Update Orchestrator scheduled tasks (expanded)
echo  [6/12] Disabling Windows Update scheduled tasks...
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
:: Additional tasks (v2)
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Backup Scan" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Maintenance Work" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Start" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Idle" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\UUS Failover Task" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\policyupdate" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Start Oobe Expedite Work" /Disable >nul 2>&1

:: 7. Block Windows Update domains via HOSTS file (expanded)
echo  [7/12] Blocking Windows Update servers in HOSTS file...
set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
:: Stop DNS client to release file lock
net stop Dnscache 2>nul
timeout /t 1 /nobreak >nul
:: Remove old block first (in case domain list changed from v1)
findstr /c:"# winDOHs-UPDATE-BLOCK-START" "%HOSTS%" >nul 2>&1
if %errorlevel% equ 0 (
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
            echo !LINE!>> "!TEMP_HOSTS!"
        )
        if "!LINE!"=="# winDOHs-UPDATE-BLOCK-END" (
            set "SKIP=0"
        )
    )
    endlocal
    copy /y "%TEMP%\hosts_clean.tmp" "%HOSTS%" >nul 2>&1
    del /f "%TEMP%\hosts_clean.tmp" >nul 2>&1
)
:: Write fresh block with expanded domain list
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
echo 0.0.0.0 ctldl.windowsupdate.com>> "%HOSTS%"
echo 0.0.0.0 settings-win.data.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 definitionupdates.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 update.microsoft.com.akadns.net>> "%HOSTS%"
echo 0.0.0.0 update.microsoft.com.nsatc.net>> "%HOSTS%"
echo 0.0.0.0 statsfe2.update.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 statsfe2.ws.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 slscr.update.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 fe2cr.update.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 us.update.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 ds.download.windowsupdate.com>> "%HOSTS%"
echo 0.0.0.0 wu.ec.azureedge.net>> "%HOSTS%"
echo 0.0.0.0 sls.update.microsoft.com.akadns.net>> "%HOSTS%"
echo 0.0.0.0 fe3.delivery.mp.microsoft.com.nsatc.net>> "%HOSTS%"
echo 0.0.0.0 tlu.dl.delivery.mp.microsoft.com>> "%HOSTS%"
echo 0.0.0.0 au.v10.vortex-win.data.microsoft.com>> "%HOSTS%"
echo # winDOHs-UPDATE-BLOCK-END>> "%HOSTS%"
:: Restart DNS client
net start Dnscache 2>nul

:: 8. Rename the Windows Update directory to prevent cached updates
echo  [8/12] Renaming SoftwareDistribution folder...
ren "%SystemRoot%\SoftwareDistribution" SoftwareDistribution.bak >nul 2>&1

:: 9. Block Windows Update exe with Windows Firewall (expanded)
echo  [9/12] Adding firewall rules to block update binaries...
netsh advfirewall firewall add rule name="winDOHs Block wuauclt" dir=out action=block program="%SystemRoot%\System32\wuauclt.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block WaaSMedic" dir=out action=block program="%SystemRoot%\System32\WaaSMedicAgent.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block UsoClient" dir=out action=block program="%SystemRoot%\System32\UsoClient.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block musNotify" dir=out action=block program="%SystemRoot%\System32\musNotification.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block musNotifyWorker" dir=out action=block program="%SystemRoot%\System32\musNotificationUx.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block UpdateAssist" dir=out action=block program="%SystemRoot%\UpdateAssistant\UpdateAssistant.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="winDOHs Block sedLauncher" dir=out action=block program="%SystemRoot%\System32\sedlauncher.exe" enable=yes >nul 2>&1

:: 10. Deny execute permissions on ALL update binaries (expanded from v1)
echo  [10/12] Revoking execute permissions on update binaries...
takeown /f "%SystemRoot%\System32\UsoClient.exe" /a >nul 2>&1
icacls "%SystemRoot%\System32\UsoClient.exe" /deny Everyone:(RX) >nul 2>&1
takeown /f "%SystemRoot%\System32\WaaSMedicAgent.exe" /a >nul 2>&1
icacls "%SystemRoot%\System32\WaaSMedicAgent.exe" /deny Everyone:(RX) >nul 2>&1
takeown /f "%SystemRoot%\System32\wuauclt.exe" /a >nul 2>&1
icacls "%SystemRoot%\System32\wuauclt.exe" /deny Everyone:(RX) >nul 2>&1
takeown /f "%SystemRoot%\System32\musNotification.exe" /a >nul 2>&1
icacls "%SystemRoot%\System32\musNotification.exe" /deny Everyone:(RX) >nul 2>&1
takeown /f "%SystemRoot%\System32\musNotificationUx.exe" /a >nul 2>&1
icacls "%SystemRoot%\System32\musNotificationUx.exe" /deny Everyone:(RX) >nul 2>&1
takeown /f "%SystemRoot%\System32\sedlauncher.exe" /a >nul 2>&1
icacls "%SystemRoot%\System32\sedlauncher.exe" /deny Everyone:(RX) >nul 2>&1

:: 11. Windows Update Assistant cleanup
echo  [11/12] Cleaning up Windows Update Assistant...
if exist "%SystemRoot%\UpdateAssistant" (
    takeown /f "%SystemRoot%\UpdateAssistant" /r /d Y /a >nul 2>&1
    icacls "%SystemRoot%\UpdateAssistant" /deny Everyone:(OI)(CI)(RX) >nul 2>&1
)

:: 12. Flush DNS
echo  [12/12] Flushing DNS cache...
ipconfig /flushdns >nul 2>&1

echo.
echo  ============================================================
echo   ALL DONE - Windows Update has been DISABLED (12 layers).
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

:: 1. Unlock service registry keys (MUST be first)
echo  [1/12] Unlocking service registry keys...
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "foreach($svc in @('wuauserv','UsoSvc','WaaSMedicSvc')){try{$p='SYSTEM\CurrentControlSet\Services\'+$svc;$k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($p,'ReadWriteSubTree',([System.Security.AccessControl.RegistryRights]::TakeOwnership-bor[System.Security.AccessControl.RegistryRights]::ChangePermissions));if(-not $k){continue};$a=$k.GetAccessControl();$admin=[System.Security.Principal.NTAccount]'BUILTIN\Administrators';$a.SetOwner($admin);foreach($r in $a.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])){if($r.AccessControlType-eq'Deny'){$a.RemoveAccessRuleSpecific($r)}};$sys=[System.Security.Principal.NTAccount]'NT AUTHORITY\SYSTEM';$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($sys,'FullControl','ContainerInherit,ObjectInherit','None','Allow')));$a.SetAccessRuleProtection($false,$false);$k.SetAccessControl($a);$k.Close()}catch{}}" >nul 2>&1

:: 2. Re-enable services + remove nulled failure actions
echo  [2/12] Re-enabling Windows Update services...
sc config wuauserv       start= demand >nul 2>&1
sc config UsoSvc         start= demand >nul 2>&1
sc config WaaSMedicSvc   start= demand >nul 2>&1
sc config bits           start= delayed-auto >nul 2>&1
sc config dosvc          start= delayed-auto >nul 2>&1
sc config uhssvc         start= demand >nul 2>&1
sc config sedsvc         start= demand >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv" /v FailureActions /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc" /v FailureActions /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v FailureActions /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\bits" /v FailureActions /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\dosvc" /v FailureActions /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\uhssvc" /v FailureActions /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\sedsvc" /v FailureActions /f >nul 2>&1

:: 3. Start services
echo  [3/12] Starting Windows Update services...
net start bits           2>nul
net start wuauserv       2>nul
net start UsoSvc         2>nul
net start dosvc          2>nul

:: 4. Remove Group Policy keys
echo  [4/12] Removing Group Policy registry keys...
:: Unlock GP key ACLs first so values can be deleted
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "foreach($p in @('SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU','SOFTWARE\Policies\Microsoft\WindowsStore')){try{$k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($p,'ReadWriteSubTree',([System.Security.AccessControl.RegistryRights]::TakeOwnership-bor[System.Security.AccessControl.RegistryRights]::ChangePermissions));if(-not $k){continue};$a=$k.GetAccessControl();$admin=[System.Security.Principal.NTAccount]'BUILTIN\Administrators';$a.SetOwner($admin);foreach($r in $a.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])){if($r.AccessControlType-eq'Deny'){$a.RemoveAccessRuleSpecific($r)}};$sys=[System.Security.Principal.NTAccount]'NT AUTHORITY\SYSTEM';$a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($sys,'FullControl','ContainerInherit,ObjectInherit','None','Allow')));$a.SetAccessRuleProtection($false,$false);$k.SetAccessControl($a);$k.Close()}catch{}}" >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DoNotConnectToWindowsUpdateInternetLocations /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWindowsUpdateAccess /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetDisableUXWUAccess /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ExcludeWUDriversInQualityUpdate /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetPolicyDrivenUpdateSourceForFeatureUpdates /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v SetPolicyDrivenUpdateSourceForQualityUpdates /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableOSUpgrade /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v ManagePreviewBuildsPolicyValue /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersion /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersionInfo /f >nul 2>&1

:: 5. Remove additional registry hardening
echo  [5/12] Removing additional registry keys...
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" /v MaintenanceDisabled /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade" /v AllowOSUpgrade /f >nul 2>&1

:: 6. Re-enable scheduled tasks
echo  [6/12] Re-enabling Windows Update scheduled tasks...
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
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Backup Scan" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Maintenance Work" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Start" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Idle" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\UUS Failover Task" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\policyupdate" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Start Oobe Expedite Work" /Enable >nul 2>&1

:: 7. Remove HOSTS file blocks
echo  [7/12] Removing HOSTS file blocks...
net stop Dnscache >nul 2>&1
timeout /t 1 /nobreak >nul
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
net start Dnscache >nul 2>&1

:: 8. Restore SoftwareDistribution folder
echo  [8/12] Restoring SoftwareDistribution folder...
ren "%SystemRoot%\SoftwareDistribution.bak" SoftwareDistribution >nul 2>&1

:: 9. Remove firewall rules
echo  [9/12] Removing firewall block rules...
netsh advfirewall firewall delete rule name="winDOHs Block wuauclt" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block WaaSMedic" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block UsoClient" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block musNotify" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block musNotifyWorker" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block UpdateAssist" >nul 2>&1
netsh advfirewall firewall delete rule name="winDOHs Block sedLauncher" >nul 2>&1

:: 10. Restore binary permissions
echo  [10/12] Restoring update binary permissions...
icacls "%SystemRoot%\System32\UsoClient.exe" /remove:d Everyone >nul 2>&1
icacls "%SystemRoot%\System32\UsoClient.exe" /grant Everyone:(RX) >nul 2>&1
icacls "%SystemRoot%\System32\UsoClient.exe" /setowner "NT SERVICE\TrustedInstaller" >nul 2>&1
icacls "%SystemRoot%\System32\WaaSMedicAgent.exe" /remove:d Everyone >nul 2>&1
icacls "%SystemRoot%\System32\WaaSMedicAgent.exe" /grant Everyone:(RX) >nul 2>&1
icacls "%SystemRoot%\System32\WaaSMedicAgent.exe" /setowner "NT SERVICE\TrustedInstaller" >nul 2>&1
icacls "%SystemRoot%\System32\wuauclt.exe" /remove:d Everyone >nul 2>&1
icacls "%SystemRoot%\System32\wuauclt.exe" /grant Everyone:(RX) >nul 2>&1
icacls "%SystemRoot%\System32\wuauclt.exe" /setowner "NT SERVICE\TrustedInstaller" >nul 2>&1
icacls "%SystemRoot%\System32\musNotification.exe" /remove:d Everyone >nul 2>&1
icacls "%SystemRoot%\System32\musNotification.exe" /grant Everyone:(RX) >nul 2>&1
icacls "%SystemRoot%\System32\musNotification.exe" /setowner "NT SERVICE\TrustedInstaller" >nul 2>&1
icacls "%SystemRoot%\System32\musNotificationUx.exe" /remove:d Everyone >nul 2>&1
icacls "%SystemRoot%\System32\musNotificationUx.exe" /grant Everyone:(RX) >nul 2>&1
icacls "%SystemRoot%\System32\musNotificationUx.exe" /setowner "NT SERVICE\TrustedInstaller" >nul 2>&1
icacls "%SystemRoot%\System32\sedlauncher.exe" /remove:d Everyone >nul 2>&1
icacls "%SystemRoot%\System32\sedlauncher.exe" /grant Everyone:(RX) >nul 2>&1
icacls "%SystemRoot%\System32\sedlauncher.exe" /setowner "NT SERVICE\TrustedInstaller" >nul 2>&1

:: 11. Restore Update Assistant permissions
echo  [11/12] Restoring Windows Update Assistant...
if exist "%SystemRoot%\UpdateAssistant" (
    icacls "%SystemRoot%\UpdateAssistant" /remove:d Everyone >nul 2>&1
    icacls "%SystemRoot%\UpdateAssistant" /grant Everyone:(OI)(CI)(RX) >nul 2>&1
    icacls "%SystemRoot%\UpdateAssistant" /setowner "NT SERVICE\TrustedInstaller" >nul 2>&1
)

:: 12. Flush DNS
echo  [12/12] Flushing DNS cache...
ipconfig /flushdns >nul 2>&1

echo.
echo  ============================================================
echo   ALL DONE - Windows Update has been RE-ENABLED.
echo   A reboot is recommended to fully apply changes.
echo  ============================================================
echo.
pause
goto MENU

:: ========================= STATUS (CHECK BLOCK) ============================
:STATUS
cls
echo.
echo  Checking Windows Update block status...
echo.
set "STATUSPS=%TEMP%\winDOHs_status.ps1"
if exist "%STATUSPS%" del /f "%STATUSPS%" >nul 2>&1
>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  ============================================================' -ForegroundColor Cyan
>>"%STATUSPS%" echo Write-Host '   WINDOWS UPDATE BLOCK STATUS CHECK' -ForegroundColor Cyan
>>"%STATUSPS%" echo Write-Host '  ============================================================' -ForegroundColor Cyan
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Services:' -ForegroundColor White
>>"%STATUSPS%" echo foreach($s in @('wuauserv','UsoSvc','WaaSMedicSvc','bits','dosvc','uhssvc','sedsvc')){
>>"%STATUSPS%" echo   $o = Get-Service $s -EA SilentlyContinue
>>"%STATUSPS%" echo   $t = (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$s) -Name Start -EA SilentlyContinue).Start
>>"%STATUSPS%" echo   if($o){
>>"%STATUSPS%" echo     $st = $o.Status
>>"%STATUSPS%" echo     $l = switch($t){0{'Boot'}1{'System'}2{'Auto'}3{'Manual'}4{'DISABLED'}default{('?'+$t)}}
>>"%STATUSPS%" echo     $c = if($t -eq 4 -and $st -eq 'Stopped'){'Green'}else{'Red'}
>>"%STATUSPS%" echo     Write-Host ('    {0,-18} {1,-10} {2}' -f $s,$st,$l) -ForegroundColor $c
>>"%STATUSPS%" echo   }else{
>>"%STATUSPS%" echo     Write-Host ('    {0,-18} Not installed' -f $s) -ForegroundColor DarkGray
>>"%STATUSPS%" echo   }
>>"%STATUSPS%" echo }
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Registry ACL lockdown:' -ForegroundColor White
>>"%STATUSPS%" echo foreach($s in @('wuauserv','UsoSvc','WaaSMedicSvc')){
>>"%STATUSPS%" echo   $lk = $false
>>"%STATUSPS%" echo   try{
>>"%STATUSPS%" echo     $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(('SYSTEM\CurrentControlSet\Services\'+$s),'Default',[System.Security.AccessControl.RegistryRights]::ReadPermissions)
>>"%STATUSPS%" echo     if($k){
>>"%STATUSPS%" echo       foreach($r in $k.GetAccessControl().GetAccessRules($true,$true,[System.Security.Principal.NTAccount])){
>>"%STATUSPS%" echo         if($r.IdentityReference.Value -eq 'NT AUTHORITY\SYSTEM' -and $r.AccessControlType -eq 'Deny'){$lk=$true;break}
>>"%STATUSPS%" echo       }
>>"%STATUSPS%" echo       $k.Close()
>>"%STATUSPS%" echo     }
>>"%STATUSPS%" echo   }catch{}
>>"%STATUSPS%" echo   $c = if($lk){'Green'}else{'Red'}
>>"%STATUSPS%" echo   Write-Host ('    {0,-18} {1}' -f $s,$(if($lk){'LOCKED'}else{'UNLOCKED'})) -ForegroundColor $c
>>"%STATUSPS%" echo }
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Group Policy ACL lockdown:' -ForegroundColor White
>>"%STATUSPS%" echo foreach($gp in @('SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU','SOFTWARE\Policies\Microsoft\WindowsStore')){
>>"%STATUSPS%" echo   $lk = $false
>>"%STATUSPS%" echo   try{
>>"%STATUSPS%" echo     $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($gp,'Default',[System.Security.AccessControl.RegistryRights]::ReadPermissions)
>>"%STATUSPS%" echo     if($k){
>>"%STATUSPS%" echo       foreach($r in $k.GetAccessControl().GetAccessRules($true,$true,[System.Security.Principal.NTAccount])){
>>"%STATUSPS%" echo         if($r.IdentityReference.Value -eq 'NT AUTHORITY\SYSTEM' -and $r.AccessControlType -eq 'Deny'){$lk=$true;break}
>>"%STATUSPS%" echo       }
>>"%STATUSPS%" echo       $k.Close()
>>"%STATUSPS%" echo     }
>>"%STATUSPS%" echo   }catch{}
>>"%STATUSPS%" echo   $c = if($lk){'Green'}else{'Red'}
>>"%STATUSPS%" echo   $sn = $gp -replace '^^SOFTWARE\\Policies\\Microsoft\\',''
>>"%STATUSPS%" echo   Write-Host ('    {0,-42} {1}' -f $sn,$(if($lk){'LOCKED'}else{'UNLOCKED'})) -ForegroundColor $c
>>"%STATUSPS%" echo }
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Group Policy:' -ForegroundColor White
>>"%STATUSPS%" echo $aup = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
>>"%STATUSPS%" echo $wup = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
>>"%STATUSPS%" echo $na = (Get-ItemProperty $aup -Name NoAutoUpdate -EA SilentlyContinue).NoAutoUpdate
>>"%STATUSPS%" echo $da = (Get-ItemProperty $wup -Name DisableWindowsUpdateAccess -EA SilentlyContinue).DisableWindowsUpdateAccess
>>"%STATUSPS%" echo $do2 = (Get-ItemProperty $wup -Name DisableOSUpgrade -EA SilentlyContinue).DisableOSUpgrade
>>"%STATUSPS%" echo $tv = (Get-ItemProperty $wup -Name TargetReleaseVersionInfo -EA SilentlyContinue).TargetReleaseVersionInfo
>>"%STATUSPS%" echo Write-Host ('    NoAutoUpdate:               ' + $na) -ForegroundColor $(if($na -eq 1){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ('    DisableWindowsUpdateAccess:  ' + $da) -ForegroundColor $(if($da -eq 1){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ('    DisableOSUpgrade:            ' + $do2) -ForegroundColor $(if($do2 -eq 1){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ('    TargetReleaseVersionInfo:    ' + $tv) -ForegroundColor $(if($tv){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Additional registry:' -ForegroundColor White
>>"%STATUSPS%" echo $md = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' -Name MaintenanceDisabled -EA SilentlyContinue).MaintenanceDisabled
>>"%STATUSPS%" echo $sa = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -Name AutoDownload -EA SilentlyContinue).AutoDownload
>>"%STATUSPS%" echo Write-Host ('    MaintenanceDisabled:         ' + $md) -ForegroundColor $(if($md -eq 1){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ('    Store AutoDownload:          ' + $sa) -ForegroundColor $(if($sa -eq 2){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Hosts file:' -ForegroundColor White
>>"%STATUSPS%" echo $hb = (Get-Content ($env:SystemRoot+'\System32\drivers\etc\hosts') -Raw -EA SilentlyContinue) -match 'winDOHs-UPDATE-BLOCK-START'
>>"%STATUSPS%" echo Write-Host ('    Update domains blocked:      ' + $hb) -ForegroundColor $(if($hb){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Firewall rules:' -ForegroundColor White
>>"%STATUSPS%" echo $ok = $true
>>"%STATUSPS%" echo foreach($n in @('winDOHs Block wuauclt','winDOHs Block WaaSMedic','winDOHs Block UsoClient','winDOHs Block musNotify','winDOHs Block musNotifyWorker','winDOHs Block UpdateAssist','winDOHs Block sedLauncher')){
>>"%STATUSPS%" echo   if(-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)){$ok = $false; break}
>>"%STATUSPS%" echo }
>>"%STATUSPS%" echo Write-Host ('    All firewall rules present:  ' + $ok) -ForegroundColor $(if($ok){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  SoftwareDistribution:' -ForegroundColor White
>>"%STATUSPS%" echo $sd = Test-Path ($env:SystemRoot+'\SoftwareDistribution')
>>"%STATUSPS%" echo $sb = Test-Path ($env:SystemRoot+'\SoftwareDistribution.bak')
>>"%STATUSPS%" echo Write-Host ('    Original exists: ' + $sd + ' / Backup exists: ' + $sb) -ForegroundColor $(if(-not $sd){'Green'}else{'Red'})
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Binary execute denied:' -ForegroundColor White
>>"%STATUSPS%" echo foreach($b in @(($env:SystemRoot+'\System32\UsoClient.exe'),($env:SystemRoot+'\System32\WaaSMedicAgent.exe'),($env:SystemRoot+'\System32\wuauclt.exe'),($env:SystemRoot+'\System32\musNotification.exe'),($env:SystemRoot+'\System32\musNotificationUx.exe'),($env:SystemRoot+'\System32\sedlauncher.exe'))){
>>"%STATUSPS%" echo   if(Test-Path $b){
>>"%STATUSPS%" echo     $ao = (^& icacls $b 2^>$null) -join ' '
>>"%STATUSPS%" echo     $d = $ao -match 'Everyone:\(DENY\)'
>>"%STATUSPS%" echo     $c = if($d){'Green'}else{'Red'}
>>"%STATUSPS%" echo     Write-Host ('    {0,-40} {1}' -f (Split-Path $b -Leaf),$(if($d){'DENIED'}else{'ALLOWED'})) -ForegroundColor $c
>>"%STATUSPS%" echo   }
>>"%STATUSPS%" echo }
>>"%STATUSPS%" echo Write-Host ''
>>"%STATUSPS%" echo Write-Host '  Legend: Green = blocked, Red = NOT blocked (potential leak)' -ForegroundColor DarkGray
>>"%STATUSPS%" echo Write-Host ''
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%STATUSPS%"
del /f "%STATUSPS%" >nul 2>&1
pause
goto MENU
