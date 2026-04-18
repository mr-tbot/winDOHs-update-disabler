<#
.SYNOPSIS
    winDOHs Update Disabler - PowerShell Edition (v2)
    Fully disables or re-enables Windows Update using multiple layered methods.

.DESCRIPTION
    This script applies 12 independent layers of protection to completely
    prevent Windows from downloading or installing updates:
        1.  Stop all update-related services
        2.  Disable all update services & null recovery actions for ALL
        3.  Lock service registry keys with ACLs (prevent self-healing)
        4.  Group Policy registry keys (comprehensive)
        5.  Additional registry hardening (maintenance, store, OS version lock)
        6.  Disable all update scheduled tasks (expanded list)
        7.  Block update domains via HOSTS file (expanded list)
        8.  Rename SoftwareDistribution cache folder
        9.  Firewall rules blocking update binaries (expanded)
        10. Deny execute permissions on all update binaries
        11. Windows Update Assistant cleanup
        12. Flush DNS cache

    Run with -Mode Install  to disable updates.
    Run with -Mode Revert   to re-enable updates.
    Run without parameters for an interactive menu.

.PARAMETER Mode
    "Install" to disable updates, "Revert" to re-enable, or omit for interactive menu.

.EXAMPLE
    .\DisableWindowsUpdate.ps1 -Mode Install
    .\DisableWindowsUpdate.ps1 -Mode Revert
    .\DisableWindowsUpdate.ps1

.NOTES
    Must be run as Administrator.
    v2 - Enhanced with ACL lockdown, failure action nulling for ALL services,
         additional services/tasks/domains, and status checker.
#>

[CmdletBinding()]
param(
    [ValidateSet("Install", "Revert")]
    [string]$Mode
)

# â”€â”€ Require elevation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function Assert-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Re-launch self elevated via UAC prompt
        $scriptPath = $MyInvocation.ScriptName
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($Mode) { $argList += " -Mode $Mode" }
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        } catch {
            Write-Host "`n  ERROR: UAC elevation was declined or failed." -ForegroundColor Red
            pause
        }
        exit
    }
}

# â”€â”€â”€ Helper: safe service config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function Set-ServiceStartupType {
    param([string]$Name, [int]$StartType, [bool]$DelayedAutostart = $false)
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "Start" -Value $StartType -ErrorAction SilentlyContinue
            if ($DelayedAutostart) {
                Set-ItemProperty -Path $regPath -Name "DelayedAutostart" -Value 1 -ErrorAction SilentlyContinue
            } elseif ($StartType -ne 2) {
                Remove-ItemProperty -Path $regPath -Name "DelayedAutostart" -ErrorAction SilentlyContinue
            }
        }
    } catch { }
}

function Stop-ServiceSafe {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Start-ServiceSafe {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            Start-Service -Name $Name -ErrorAction SilentlyContinue
        }
    } catch { }
}

# â”€â”€â”€ Helper: null out service failure/recovery actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function Set-ServiceFailureActionsToNone {
    param([string]$Name)
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        if (Test-Path $regPath) {
            # Struct: resetPeriod=0, rebootMsg=0, command=0, numActions=3, actionsSize=20,
            # then 3x {type=SC_ACTION_NONE(0), delay=60000ms}
            $failBytes = [byte[]](0,0,0,0, 0,0,0,0, 0,0,0,0, 3,0,0,0, 20,0,0,0,
                                  0,0,0,0, 0x60,0xEA,0,0, 0,0,0,0, 0x60,0xEA,0,0,
                                  0,0,0,0, 0x60,0xEA,0,0)
            Set-ItemProperty -Path $regPath -Name "FailureActions" -Value $failBytes -ErrorAction SilentlyContinue
        }
    } catch { }
}
# â"€â"€â"€ Helper: robust registry write with key creation + verify â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
$script:regFailures = @()

function Force-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        # Verify readback
        $readback = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($Type -eq "DWord" -and [int]$readback -ne [int]$Value) {
            throw "Readback mismatch: wrote $Value, read $readback"
        }
        if ($Type -eq "String" -and "$readback" -ne "$Value") {
            throw "Readback mismatch: wrote '$Value', read '$readback'"
        }
    } catch {
        $script:regFailures += "    $Path\$Name = $($_.Exception.Message)"
    }
}

# â"€â"€â"€ Helper: lock a registry key's ACLs (deny SYSTEM writes) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
function Lock-RegistryKeyACL {
    param([string]$RegPath)
    try {
        # Take ownership as Administrators
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $RegPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::TakeOwnership
        )
        if (-not $key) { return $false }

        $acl   = $key.GetAccessControl()
        $admin = [System.Security.Principal.NTAccount]"BUILTIN\Administrators"
        $acl.SetOwner($admin)
        $key.SetAccessControl($acl)
        $key.Close()

        # Reopen with ChangePermissions
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $RegPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            ([System.Security.AccessControl.RegistryRights]::ChangePermissions -bor
             [System.Security.AccessControl.RegistryRights]::ReadKey)
        )
        if (-not $key) { return $false }

        $acl = $key.GetAccessControl()
        $acl.SetAccessRuleProtection($true, $false)

        # Use SID-based enumeration to avoid translation errors from orphaned SIDs
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            $acl.RemoveAccessRuleSpecific($rule)
        }

        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $admin, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

        $system = [System.Security.Principal.NTAccount]"NT AUTHORITY\SYSTEM"
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $system, "ReadKey", "ContainerInherit,ObjectInherit", "None", "Allow")))

        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $system, "SetValue,CreateSubKey,Delete", "ContainerInherit,ObjectInherit", "None", "Deny")))

        $key.SetAccessControl($acl)
        $key.Close()
        return $true
    } catch {
        return $false
    }
}

function Unlock-RegistryKeyACL {
    param([string]$RegPath)
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $RegPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            ([System.Security.AccessControl.RegistryRights]::TakeOwnership -bor
             [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        )
        if (-not $key) { return }

        $acl   = $key.GetAccessControl()
        $admin = [System.Security.Principal.NTAccount]"BUILTIN\Administrators"
        $acl.SetOwner($admin)

        # Use SID-based enumeration to avoid translation errors from orphaned SIDs
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq 'Deny') {
                $acl.RemoveAccessRuleSpecific($rule)
            }
        }

        $system = [System.Security.Principal.NTAccount]"NT AUTHORITY\SYSTEM"
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $system, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

        $acl.SetAccessRuleProtection($false, $false)
        $key.SetAccessControl($acl)
        $key.Close()
    } catch { }
}
# â”€â”€â”€ Helper: lock service registry key ACLs (prevent SYSTEM from re-enabling) â”€
function Lock-ServiceRegistryKey {
    param([string]$ServiceName)
    try {
        $regPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"

        # Take ownership as Administrators
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $regPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::TakeOwnership
        )
        if (-not $key) { return }

        $acl   = $key.GetAccessControl()
        $admin = [System.Security.Principal.NTAccount]"BUILTIN\Administrators"
        $acl.SetOwner($admin)
        $key.SetAccessControl($acl)
        $key.Close()

        # Reopen with ChangePermissions
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $regPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            ([System.Security.AccessControl.RegistryRights]::ChangePermissions -bor
             [System.Security.AccessControl.RegistryRights]::ReadKey)
        )
        if (-not $key) { return }

        $acl = $key.GetAccessControl()

        # Break inheritance, wipe all existing rules
        $acl.SetAccessRuleProtection($true, $false)

        # Use SID-based enumeration to avoid translation errors from orphaned SIDs
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            $acl.RemoveAccessRuleSpecific($rule)
        }

        # Administrators: Full Control
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $admin, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

        # SYSTEM: Read only
        $system = [System.Security.Principal.NTAccount]"NT AUTHORITY\SYSTEM"
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $system, "ReadKey", "ContainerInherit,ObjectInherit", "None", "Allow")))

        # SYSTEM: DENY write operations - this is the critical line that prevents
        # WaaSMedic and other self-healing from changing the Start value back
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $system, "SetValue,CreateSubKey,Delete", "ContainerInherit,ObjectInherit", "None", "Deny")))

        $key.SetAccessControl($acl)
        $key.Close()
    } catch {
        Write-Verbose "  Could not lock $ServiceName registry key: $_"
    }
}

function Unlock-ServiceRegistryKey {
    param([string]$ServiceName)
    try {
        $regPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"

        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $regPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            ([System.Security.AccessControl.RegistryRights]::TakeOwnership -bor
             [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        )
        if (-not $key) { return }

        $acl   = $key.GetAccessControl()
        $admin = [System.Security.Principal.NTAccount]"BUILTIN\Administrators"
        $acl.SetOwner($admin)

        # Remove all Deny rules (use SID-based enumeration to avoid orphaned SID errors)
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq 'Deny') {
                $acl.RemoveAccessRuleSpecific($rule)
            }
        }

        # Restore SYSTEM Full Control
        $system = [System.Security.Principal.NTAccount]"NT AUTHORITY\SYSTEM"
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
            $system, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

        # Re-enable inheritance
        $acl.SetAccessRuleProtection($false, $false)

        $key.SetAccessControl($acl)
        $key.Close()
    } catch {
        Write-Verbose "  Could not unlock $ServiceName registry key: $_"
    }
}

# â”€â”€â”€ HOSTS file helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$hostsPath   = "$env:SystemRoot\System32\drivers\etc\hosts"
$blockStart  = "# winDOHs-UPDATE-BLOCK-START"
$blockEnd    = "# winDOHs-UPDATE-BLOCK-END"

function Write-HostsFile {
    param(
        [string]$Path,
        [string[]]$Content,
        [int]$Retries = 5,
        [int]$DelayMs = 2000
    )
    # Pre-emptively stop DNS client which commonly locks the hosts file
    $dnsWasRunning = (Get-Service -Name Dnscache -ErrorAction SilentlyContinue).Status -eq 'Running'
    if ($dnsWasRunning) {
        Stop-Service -Name Dnscache -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1000
    }
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Set-Content -Path $Path -Value $Content -Encoding ASCII -Force -ErrorAction Stop
            return $true
        } catch {
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    Write-Warning "         Failed to write $Path after $Retries attempts."
    return $false
}

$updateDomains = @(
    "windowsupdate.microsoft.com"
    "update.microsoft.com"
    "windowsupdate.com"
    "download.windowsupdate.com"
    "download.microsoft.com"
    "wustat.windows.com"
    "ntservicepack.microsoft.com"
    "go.microsoft.com"
    "dl.delivery.mp.microsoft.com"
    "sls.update.microsoft.com"
    "fe2.update.microsoft.com"
    "fe3.delivery.mp.microsoft.com"
    "tsfe.trafficshaping.dsp.mp.microsoft.com"
    "emdl.ws.microsoft.com"
    "ctldl.windowsupdate.com"
    "settings-win.data.microsoft.com"
    # â”€â”€ Additional domains (v2) â”€â”€
    "definitionupdates.microsoft.com"
    "update.microsoft.com.akadns.net"
    "update.microsoft.com.nsatc.net"
    "statsfe2.update.microsoft.com"
    "statsfe2.ws.microsoft.com"
    "slscr.update.microsoft.com"
    "fe2cr.update.microsoft.com"
    "us.update.microsoft.com"
    "ds.download.windowsupdate.com"
    "wu.ec.azureedge.net"
    "sls.update.microsoft.com.akadns.net"
    "fe3.delivery.mp.microsoft.com.nsatc.net"
    "tlu.dl.delivery.mp.microsoft.com"
    "au.v10.vortex-win.data.microsoft.com"
)

# â”€â”€â”€ Services to manage â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$updateServices = @(
    @{ Name = "wuauserv";      DefaultStart = 3; DelayedAuto = $false }   # Windows Update
    @{ Name = "UsoSvc";        DefaultStart = 3; DelayedAuto = $false }   # Update Orchestrator
    @{ Name = "WaaSMedicSvc";  DefaultStart = 3; DelayedAuto = $false }   # Windows Update Medic
    @{ Name = "bits";          DefaultStart = 2; DelayedAuto = $true  }   # Background Intelligent Transfer
    @{ Name = "dosvc";         DefaultStart = 2; DelayedAuto = $true  }   # Delivery Optimization
    @{ Name = "uhssvc";        DefaultStart = 3; DelayedAuto = $false }   # Microsoft Update Health
    @{ Name = "sedsvc";        DefaultStart = 3; DelayedAuto = $false }   # Windows Remediation Service
)

# Critical services whose registry keys we lock with ACLs
$lockdownServices = @("wuauserv", "UsoSvc", "WaaSMedicSvc")

# â”€â”€â”€ Scheduled Tasks to manage â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$updateTasks = @(
    "\Microsoft\Windows\WindowsUpdate\Scheduled Start"
    "\Microsoft\Windows\WindowsUpdate\sih"
    "\Microsoft\Windows\WindowsUpdate\sihboot"
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan"
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task"
    "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask"
    "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker"
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Work"
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Wake To Work"
    "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC"
    "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery"
    "\Microsoft\Windows\UpdateOrchestrator\Report policies"
    "\Microsoft\Windows\WaaSMedic\PerformRemediation"
    # â”€â”€ Additional tasks (v2) â”€â”€
    "\Microsoft\Windows\UpdateOrchestrator\Backup Scan"
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Maintenance Work"
    "\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Start"
    "\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Idle"
    "\Microsoft\Windows\UpdateOrchestrator\UUS Failover Task"
    "\Microsoft\Windows\UpdateOrchestrator\policyupdate"
    "\Microsoft\Windows\UpdateOrchestrator\Start Oobe Expedite Work"
)

# â”€â”€â”€ Firewall rules â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$firewallRules = @(
    @{ Name = "winDOHs Block wuauclt";          Program = "$env:SystemRoot\System32\wuauclt.exe" }
    @{ Name = "winDOHs Block WaaSMedic";        Program = "$env:SystemRoot\System32\WaaSMedicAgent.exe" }
    @{ Name = "winDOHs Block UsoClient";        Program = "$env:SystemRoot\System32\UsoClient.exe" }
    @{ Name = "winDOHs Block musNotify";        Program = "$env:SystemRoot\System32\musNotification.exe" }
    @{ Name = "winDOHs Block musNotifyWorker";  Program = "$env:SystemRoot\System32\musNotificationUx.exe" }
    @{ Name = "winDOHs Block UpdateAssist";     Program = "$env:SystemRoot\UpdateAssistant\UpdateAssistant.exe" }
    @{ Name = "winDOHs Block sedLauncher";      Program = "$env:SystemRoot\System32\sedlauncher.exe" }
)

# â”€â”€â”€ Update binaries to deny execute â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$updateBinaries = @(
    "$env:SystemRoot\System32\UsoClient.exe"
    "$env:SystemRoot\System32\WaaSMedicAgent.exe"
    "$env:SystemRoot\System32\wuauclt.exe"
    "$env:SystemRoot\System32\musNotification.exe"
    "$env:SystemRoot\System32\musNotificationUx.exe"
    "$env:SystemRoot\System32\sedlauncher.exe"
)

# â”€â”€â”€ Group Policy registry paths â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$gpKeyAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$gpKeyWU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# ===========================================================================
#  INSTALL â€” Disable & block all Windows Updates (12 layers)
# ===========================================================================
function Invoke-Install {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   DISABLING ALL WINDOWS UPDATES (v2 - Enhanced)..." -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    # â”€â”€ 1. Stop services â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [1/12] Stopping Windows Update services..." -ForegroundColor Yellow
    foreach ($svc in $updateServices) {
        Stop-ServiceSafe -Name $svc.Name
    }

    # â”€â”€ 2. Disable services + null ALL recovery actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [2/12] Disabling services & nullifying recovery actions..." -ForegroundColor Yellow
    foreach ($svc in $updateServices) {
        Set-ServiceStartupType -Name $svc.Name -StartType 4  # 4 = Disabled
        Set-ServiceFailureActionsToNone -Name $svc.Name
    }

    # â”€â”€ 3. Lock service registry keys with ACLs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [3/12] Locking service registry keys (anti-tamper)..." -ForegroundColor Yellow
    Write-Host "         (Denies SYSTEM write access to prevent self-healing)" -ForegroundColor DarkGray
    foreach ($svc in $lockdownServices) {
        Lock-ServiceRegistryKey -ServiceName $svc
    }

    # â”€â”€ 4. Group Policy registry keys â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [4/12] Applying Group Policy registry keys..." -ForegroundColor Yellow
    $script:regFailures = @()

    Force-RegistryValue -Path $gpKeyAU -Name "NoAutoUpdate"                                        -Value 1
    Force-RegistryValue -Path $gpKeyAU -Name "AUOptions"                                           -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "DoNotConnectToWindowsUpdateInternetLocations"         -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "DisableWindowsUpdateAccess"                          -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "SetDisableUXWUAccess"                                -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "ExcludeWUDriversInQualityUpdate"                     -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "SetPolicyDrivenUpdateSourceForFeatureUpdates"         -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "SetPolicyDrivenUpdateSourceForQualityUpdates"         -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "DisableOSUpgrade"                                    -Value 1
    Force-RegistryValue -Path $gpKeyWU -Name "ManagePreviewBuildsPolicyValue"                      -Value 1

    # â”€â”€ 5. Additional registry hardening â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [5/12] Applying additional registry hardening..." -ForegroundColor Yellow

    # Disable automatic maintenance (triggers update scans)
    Force-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name "MaintenanceDisabled" -Value 1

    # Disable Windows Store auto-updates
    Force-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "AutoDownload" -Value 2

    # Lock to current OS version (prevent feature updates)
    $currentBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
    if (-not $currentBuild) {
        $currentBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ReleaseId -ErrorAction SilentlyContinue).ReleaseId
    }
    if ($currentBuild) {
        Force-RegistryValue -Path $gpKeyWU -Name "TargetReleaseVersion"     -Value 1
        Force-RegistryValue -Path $gpKeyWU -Name "TargetReleaseVersionInfo" -Value $currentBuild -Type "String"
        Write-Host "         Locked to OS version: $currentBuild" -ForegroundColor DarkGray
    }

    # Disable OS upgrade via another codepath
    Force-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade" -Name "AllowOSUpgrade" -Value 0

    # Lock GP registry keys with ACLs to prevent SYSTEM from reverting them
    Write-Host "         Locking Group Policy keys against SYSTEM writes..." -ForegroundColor DarkGray
    $gpLockPaths = @(
        "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU",
        "SOFTWARE\Policies\Microsoft\WindowsStore"
    )
    foreach ($gp in $gpLockPaths) {
        if (-not (Lock-RegistryKeyACL -RegPath $gp)) {
            Write-Host "         WARNING: Could not lock $gp" -ForegroundColor Red
        }
    }

    # Report any registry write failures
    if ($script:regFailures.Count -gt 0) {
        Write-Host "         WARNING: $($script:regFailures.Count) registry write(s) failed:" -ForegroundColor Red
        foreach ($f in $script:regFailures) { Write-Host $f -ForegroundColor Red }
    } else {
        Write-Host "         All registry values verified." -ForegroundColor DarkGray
    }

    # â”€â”€ 6. Disable Scheduled Tasks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [6/12] Disabling Windows Update scheduled tasks..." -ForegroundColor Yellow
    foreach ($task in $updateTasks) {
        try {
            Disable-ScheduledTask -TaskName (Split-Path $task -Leaf) -TaskPath (Split-Path $task -Parent) -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }

    # â”€â”€ 7. Block domains in HOSTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [7/12] Blocking Windows Update servers in HOSTS file..." -ForegroundColor Yellow
    # Remove old block first (in case domain list changed from v1)
    if (Test-Path $hostsPath) {
        $lines = Get-Content -Path $hostsPath
        $clean = @()
        $skip  = $false
        foreach ($line in $lines) {
            if ($line -eq $blockStart) { $skip = $true; continue }
            if ($line -eq $blockEnd)   { $skip = $false; continue }
            if (-not $skip) { $clean += $line }
        }
    } else {
        $clean = @()
    }
    # Append fresh block with expanded domain list
    $clean += ""
    $clean += $blockStart
    foreach ($domain in $updateDomains) {
        $clean += "0.0.0.0 $domain"
    }
    $clean += $blockEnd
    # Write in one shot with retry (stops DNS client if locked)
    $dnsWasRunning = (Get-Service -Name Dnscache -ErrorAction SilentlyContinue).Status -eq 'Running'
    if (-not (Write-HostsFile -Path $hostsPath -Content $clean)) {
        Write-Host "         HOSTS file write FAILED - file was locked." -ForegroundColor Red
    }
    if ($dnsWasRunning) { Start-Service -Name Dnscache -ErrorAction SilentlyContinue }

    # â”€â”€ 8. Rename SoftwareDistribution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [8/12] Renaming SoftwareDistribution folder..." -ForegroundColor Yellow
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $sdPath) {
        Rename-Item -Path $sdPath -NewName "SoftwareDistribution.bak" -Force -ErrorAction SilentlyContinue
    }

    # â”€â”€ 9. Firewall rules â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [9/12] Adding firewall rules to block update binaries..." -ForegroundColor Yellow
    foreach ($rule in $firewallRules) {
        try {
            $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            if (-not $existing) {
                New-NetFirewallRule -DisplayName $rule.Name -Direction Outbound -Action Block `
                    -Program $rule.Program -Enabled True -Profile Any -ErrorAction SilentlyContinue | Out-Null
            }
        } catch { }
    }

    # â”€â”€ 10. Deny execute on update binaries â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [10/12] Revoking execute permissions on update binaries..." -ForegroundColor Yellow
    foreach ($binary in $updateBinaries) {
        if (Test-Path $binary) {
            & takeown /f $binary /a 2>$null | Out-Null
            & icacls $binary /deny "Everyone:(RX)" 2>$null | Out-Null
        }
    }

    # â”€â”€ 11. Windows Update Assistant cleanup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [11/12] Cleaning up Windows Update Assistant..." -ForegroundColor Yellow
    $wuaPath = "$env:SystemRoot\UpdateAssistant"
    if (Test-Path $wuaPath) {
        & takeown /f "$wuaPath" /r /d Y /a 2>$null | Out-Null
        & icacls "$wuaPath" /deny "Everyone:(OI)(CI)(RX)" 2>$null | Out-Null
    }

    # â”€â”€ 12. Flush DNS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [12/12] Flushing DNS cache..." -ForegroundColor Yellow
    ipconfig /flushdns 2>$null | Out-Null

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host "   ALL DONE - Windows Update has been DISABLED (12 layers)." -ForegroundColor Green
    Write-Host "   A reboot is recommended to fully apply changes." -ForegroundColor Green
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host ""
}

# ===========================================================================
#  REVERT â€” Re-enable Windows Updates
# ===========================================================================
function Invoke-Revert {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   RE-ENABLING WINDOWS UPDATES..." -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    # â”€â”€ 1. Unlock service registry keys (MUST be first) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [1/12] Unlocking service registry keys..." -ForegroundColor Yellow
    foreach ($svc in $lockdownServices) {
        Unlock-ServiceRegistryKey -ServiceName $svc
    }

    # â”€â”€ 2. Re-enable services + remove nulled failure actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [2/12] Re-enabling Windows Update services..." -ForegroundColor Yellow
    foreach ($svc in $updateServices) {
        Set-ServiceStartupType -Name $svc.Name -StartType $svc.DefaultStart -DelayedAutostart $svc.DelayedAuto
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
        if (Test-Path $regPath) {
            Remove-ItemProperty -Path $regPath -Name "FailureActions" -ErrorAction SilentlyContinue
        }
    }

    # â”€â”€ 3. Start services â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [3/12] Starting Windows Update services..." -ForegroundColor Yellow
    foreach ($svc in @("bits", "wuauserv", "UsoSvc", "dosvc")) {
        Start-ServiceSafe -Name $svc
    }

    # â”€â”€ 4. Remove Group Policy keys â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [4/12] Removing Group Policy registry keys..." -ForegroundColor Yellow
    # Unlock GP key ACLs first so values can be removed
    $gpLockPaths = @(
        "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU",
        "SOFTWARE\Policies\Microsoft\WindowsStore"
    )
    foreach ($gp in $gpLockPaths) {
        Unlock-RegistryKeyACL -RegPath $gp
    }

    $gpValuesToRemove = @(
        @{ Path = $gpKeyAU; Name = "NoAutoUpdate" },
        @{ Path = $gpKeyAU; Name = "AUOptions" },
        @{ Path = $gpKeyWU; Name = "DoNotConnectToWindowsUpdateInternetLocations" },
        @{ Path = $gpKeyWU; Name = "DisableWindowsUpdateAccess" },
        @{ Path = $gpKeyWU; Name = "SetDisableUXWUAccess" },
        @{ Path = $gpKeyWU; Name = "ExcludeWUDriversInQualityUpdate" },
        @{ Path = $gpKeyWU; Name = "SetPolicyDrivenUpdateSourceForFeatureUpdates" },
        @{ Path = $gpKeyWU; Name = "SetPolicyDrivenUpdateSourceForQualityUpdates" },
        @{ Path = $gpKeyWU; Name = "DisableOSUpgrade" },
        @{ Path = $gpKeyWU; Name = "ManagePreviewBuildsPolicyValue" },
        @{ Path = $gpKeyWU; Name = "TargetReleaseVersion" },
        @{ Path = $gpKeyWU; Name = "TargetReleaseVersionInfo" }
    )
    foreach ($val in $gpValuesToRemove) {
        if (Test-Path $val.Path) {
            Remove-ItemProperty -Path $val.Path -Name $val.Name -ErrorAction SilentlyContinue
        }
    }

    # â”€â”€ 5. Remove additional registry hardening â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [5/12] Removing additional registry keys..." -ForegroundColor Yellow
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" `
        -Name "MaintenanceDisabled" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" `
        -Name "AutoDownload" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade" `
        -Name "AllowOSUpgrade" -ErrorAction SilentlyContinue

    # â”€â”€ 6. Re-enable Scheduled Tasks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [6/12] Re-enabling Windows Update scheduled tasks..." -ForegroundColor Yellow
    foreach ($task in $updateTasks) {
        try {
            Enable-ScheduledTask -TaskName (Split-Path $task -Leaf) -TaskPath (Split-Path $task -Parent) -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }

    # â”€â”€ 7. Remove HOSTS blocks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [7/12] Removing HOSTS file blocks..." -ForegroundColor Yellow
    if (Test-Path $hostsPath) {
        $lines = Get-Content -Path $hostsPath
        $clean = @()
        $skip  = $false
        foreach ($line in $lines) {
            if ($line -eq $blockStart) { $skip = $true; continue }
            if ($line -eq $blockEnd)   { $skip = $false; continue }
            if (-not $skip) { $clean += $line }
        }
        $dnsWasRunning = (Get-Service -Name Dnscache -ErrorAction SilentlyContinue).Status -eq 'Running'
        if (-not (Write-HostsFile -Path $hostsPath -Content $clean)) {
            Write-Host "         HOSTS file write FAILED - file was locked." -ForegroundColor Red
        }
        if ($dnsWasRunning) { Start-Service -Name Dnscache -ErrorAction SilentlyContinue }
    }

    # â”€â”€ 8. Restore SoftwareDistribution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [8/12] Restoring SoftwareDistribution folder..." -ForegroundColor Yellow
    $sdBackup = "$env:SystemRoot\SoftwareDistribution.bak"
    if (Test-Path $sdBackup) {
        Rename-Item -Path $sdBackup -NewName "SoftwareDistribution" -Force -ErrorAction SilentlyContinue
    }

    # â”€â”€ 9. Remove firewall rules â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [9/12] Removing firewall block rules..." -ForegroundColor Yellow
    foreach ($rule in $firewallRules) {
        Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    }

    # â”€â”€ 10. Restore binary permissions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [10/12] Restoring update binary permissions..." -ForegroundColor Yellow
    foreach ($binary in $updateBinaries) {
        if (Test-Path $binary) {
            & icacls $binary /remove:d "Everyone" 2>$null | Out-Null
            & icacls $binary /grant "Everyone:(RX)" 2>$null | Out-Null
            & icacls $binary /setowner "NT SERVICE\TrustedInstaller" 2>$null | Out-Null
        }
    }

    # â”€â”€ 11. Restore Update Assistant permissions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [11/12] Restoring Windows Update Assistant..." -ForegroundColor Yellow
    $wuaPath = "$env:SystemRoot\UpdateAssistant"
    if (Test-Path $wuaPath) {
        & icacls "$wuaPath" /remove:d "Everyone" 2>$null | Out-Null
        & icacls "$wuaPath" /grant "Everyone:(OI)(CI)(RX)" 2>$null | Out-Null
        & icacls "$wuaPath" /setowner "NT SERVICE\TrustedInstaller" 2>$null | Out-Null
    }

    # â”€â”€ 12. Flush DNS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Host "  [12/12] Flushing DNS cache..." -ForegroundColor Yellow
    ipconfig /flushdns 2>$null | Out-Null

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host "   ALL DONE - Windows Update has been RE-ENABLED." -ForegroundColor Green
    Write-Host "   A reboot is recommended to fully apply changes." -ForegroundColor Green
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host ""
}

# ===========================================================================
#  STATUS â€” Check current block status
# ===========================================================================
function Invoke-Status {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   WINDOWS UPDATE BLOCK STATUS CHECK" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Check services
    Write-Host "  Services:" -ForegroundColor White
    foreach ($svc in $updateServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
        $startType = (Get-ItemProperty -Path $regPath -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($service) {
            $status = $service.Status
            $startLabel = switch ($startType) { 0 {"Boot"} 1 {"System"} 2 {"Auto"} 3 {"Manual"} 4 {"DISABLED"} default {"Unknown($startType)"} }
            $color = if ($startType -eq 4 -and $status -eq 'Stopped') { 'Green' } else { 'Red' }
            Write-Host ("    {0,-18} {1,-10} {2}" -f $svc.Name, $status, $startLabel) -ForegroundColor $color
        } else {
            Write-Host ("    {0,-18} Not installed" -f $svc.Name) -ForegroundColor DarkGray
        }
    }

    # Check ACL lockdown
    Write-Host ""
    Write-Host "  Registry ACL lockdown:" -ForegroundColor White
    foreach ($svc in $lockdownServices) {
        $locked = $false
        try {
            $regPath = "SYSTEM\CurrentControlSet\Services\$svc"
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regPath,
                [Microsoft.Win32.RegistryKeyPermissionCheck]::Default,
                [System.Security.AccessControl.RegistryRights]::ReadPermissions)
            if ($key) {
                $acl = $key.GetAccessControl()
                foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])) {
                    if ($rule.IdentityReference.Value -eq "NT AUTHORITY\SYSTEM" -and $rule.AccessControlType -eq 'Deny') {
                        $locked = $true; break
                    }
                }
                $key.Close()
            }
        } catch { }
        $color = if ($locked) { 'Green' } else { 'Red' }
        $label = if ($locked) { 'LOCKED' } else { 'UNLOCKED' }
        Write-Host ("    {0,-18} {1}" -f $svc, $label) -ForegroundColor $color
    }

    # Check GP key ACL lockdown
    Write-Host ""
    Write-Host "  Group Policy ACL lockdown:" -ForegroundColor White
    $gpLockPaths = @(
        "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU",
        "SOFTWARE\Policies\Microsoft\WindowsStore"
    )
    foreach ($gp in $gpLockPaths) {
        $locked = $false
        try {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($gp,
                [Microsoft.Win32.RegistryKeyPermissionCheck]::Default,
                [System.Security.AccessControl.RegistryRights]::ReadPermissions)
            if ($key) {
                $acl = $key.GetAccessControl()
                foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])) {
                    if ($rule.IdentityReference.Value -eq "NT AUTHORITY\SYSTEM" -and $rule.AccessControlType -eq 'Deny') {
                        $locked = $true; break
                    }
                }
                $key.Close()
            }
        } catch { }
        $color = if ($locked) { 'Green' } else { 'Red' }
        $label = if ($locked) { 'LOCKED' } else { 'UNLOCKED' }
        $shortName = $gp -replace '^SOFTWARE\\Policies\\Microsoft\\', ''
        Write-Host ("    {0,-42} {1}" -f $shortName, $label) -ForegroundColor $color
    }

    # Check GP keys
    Write-Host ""
    Write-Host "  Group Policy:" -ForegroundColor White
    $noAuto        = (Get-ItemProperty -Path $gpKeyAU -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
    $disableAccess = (Get-ItemProperty -Path $gpKeyWU -Name "DisableWindowsUpdateAccess" -ErrorAction SilentlyContinue).DisableWindowsUpdateAccess
    $disableOS     = (Get-ItemProperty -Path $gpKeyWU -Name "DisableOSUpgrade" -ErrorAction SilentlyContinue).DisableOSUpgrade
    $targetVer     = (Get-ItemProperty -Path $gpKeyWU -Name "TargetReleaseVersionInfo" -ErrorAction SilentlyContinue).TargetReleaseVersionInfo

    $c1 = if ($noAuto -eq 1)        { 'Green' } else { 'Red' }
    $c2 = if ($disableAccess -eq 1)  { 'Green' } else { 'Red' }
    $c3 = if ($disableOS -eq 1)      { 'Green' } else { 'Red' }
    $c4 = if ($targetVer)            { 'Green' } else { 'Red' }
    Write-Host "    NoAutoUpdate:               $noAuto"         -ForegroundColor $c1
    Write-Host "    DisableWindowsUpdateAccess:  $disableAccess"  -ForegroundColor $c2
    Write-Host "    DisableOSUpgrade:            $disableOS"      -ForegroundColor $c3
    Write-Host "    TargetReleaseVersionInfo:    $targetVer"      -ForegroundColor $c4

    # Check additional registry
    Write-Host ""
    Write-Host "  Additional registry:" -ForegroundColor White
    $maintDisabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name "MaintenanceDisabled" -ErrorAction SilentlyContinue).MaintenanceDisabled
    $storeAuto     = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "AutoDownload" -ErrorAction SilentlyContinue).AutoDownload
    $c5 = if ($maintDisabled -eq 1) { 'Green' } else { 'Red' }
    $c6 = if ($storeAuto -eq 2)     { 'Green' } else { 'Red' }
    Write-Host "    MaintenanceDisabled:         $maintDisabled"  -ForegroundColor $c5
    Write-Host "    Store AutoDownload:          $storeAuto"      -ForegroundColor $c6

    # Check hosts
    Write-Host ""
    Write-Host "  Hosts file:" -ForegroundColor White
    $hostsContent = Get-Content -Path $hostsPath -Raw -ErrorAction SilentlyContinue
    $hostsBlocked = $hostsContent -match [regex]::Escape($blockStart)
    $c7 = if ($hostsBlocked) { 'Green' } else { 'Red' }
    Write-Host "    Update domains blocked:      $hostsBlocked"   -ForegroundColor $c7

    # Check firewall rules
    Write-Host ""
    Write-Host "  Firewall rules:" -ForegroundColor White
    $rulesOK = $true
    foreach ($rule in $firewallRules) {
        $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
        if (-not $existing) { $rulesOK = $false; break }
    }
    $c8 = if ($rulesOK) { 'Green' } else { 'Red' }
    Write-Host "    All firewall rules present:  $rulesOK"        -ForegroundColor $c8

    # Check SoftwareDistribution
    Write-Host ""
    Write-Host "  SoftwareDistribution:" -ForegroundColor White
    $sdExists    = Test-Path "$env:SystemRoot\SoftwareDistribution"
    $sdBakExists = Test-Path "$env:SystemRoot\SoftwareDistribution.bak"
    $c9 = if (-not $sdExists) { 'Green' } else { 'Red' }
    Write-Host "    Original exists: $sdExists / Backup exists: $sdBakExists" -ForegroundColor $c9

    # Check binary permissions
    Write-Host ""
    Write-Host "  Binary execute denied:" -ForegroundColor White
    foreach ($binary in $updateBinaries) {
        if (Test-Path $binary) {
            $aclOutput = (& icacls $binary 2>$null) -join " "
            $denied = $aclOutput -match "Everyone:\(DENY\)"
            $c = if ($denied) { 'Green' } else { 'Red' }
            $label = if ($denied) { 'DENIED' } else { 'ALLOWED' }
            Write-Host ("    {0,-40} {1}" -f (Split-Path $binary -Leaf), $label) -ForegroundColor $c
        }
    }

    Write-Host ""
    Write-Host "  Legend: Green = blocked, Red = NOT blocked (potential leak)" -ForegroundColor DarkGray
    Write-Host ""
}

# ===========================================================================
#  MAIN
# ===========================================================================
Assert-Admin

if ($Mode) {
    switch ($Mode) {
        "Install" { Invoke-Install }
        "Revert"  { Invoke-Revert  }
    }
} else {
    # Interactive menu
    do {
        Clear-Host
        Write-Host ""
        Write-Host "  ============================================================" -ForegroundColor Cyan
        Write-Host "       winDOHs Update Disabler  -  PowerShell Edition (v2)" -ForegroundColor Cyan
        Write-Host "  ============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    [1] INSTALL  - Disable & Block ALL Windows Updates"
        Write-Host "    [2] REVERT   - Re-enable Windows Updates"
        Write-Host "    [3] STATUS   - Check current block status"
        Write-Host "    [4] EXIT"
        Write-Host ""
        $choice = Read-Host "  Select an option (1/2/3/4)"

        switch ($choice) {
            "1" { Invoke-Install; pause }
            "2" { Invoke-Revert;  pause }
            "3" { Invoke-Status;  pause }
            "4" { return }
        }
    } while ($true)
}
