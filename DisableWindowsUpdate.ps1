<#
.SYNOPSIS
    winDOHs Update Disabler - PowerShell Edition 
    Fully disables or re-enables Windows Update using multiple layered methods.

.DESCRIPTION
    This script applies 8 independent layers of protection to completely
    prevent Windows from downloading or installing updates:
        1. Stop & disable all update-related services
        2. Lock WaaSMedicSvc self-healing
        3. Group Policy registry keys
        4. Disable scheduled tasks (WindowsUpdate, UpdateOrchestrator, WaaSMedic)
        5. Block update domains via HOSTS file
        6. Rename SoftwareDistribution cache folder
        7. Firewall rules blocking update binaries
        8. Take ownership & revoke permissions on UsoClient.exe

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
#>

[CmdletBinding()]
param(
    [ValidateSet("Install", "Revert")]
    [string]$Mode
)

# ── Require elevation ──────────────────────────────────────────────────────────
function Assert-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "`n  ERROR: This script must be run as Administrator." -ForegroundColor Red
        Write-Host "  Right-click PowerShell and choose 'Run as administrator'.`n" -ForegroundColor Red
        pause
        exit 1
    }
}

# ─── Helper: safe service config ──────────────────────────────────────────────
function Set-ServiceStartupType {
    param([string]$Name, [int]$StartType)
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "Start" -Value $StartType -ErrorAction SilentlyContinue
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

# ─── HOSTS file helpers ──────────────────────────────────────────────────────
$hostsPath   = "$env:SystemRoot\System32\drivers\etc\hosts"
$blockStart  = "# winDOHs-UPDATE-BLOCK-START"
$blockEnd    = "# winDOHs-UPDATE-BLOCK-END"

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
)

# ─── Services to manage ─────────────────────────────────────────────────────
$updateServices = @(
    @{ Name = "wuauserv";      DefaultStart = 3 }   # Manual (Demand)
    @{ Name = "UsoSvc";        DefaultStart = 3 }   # Manual (Demand)
    @{ Name = "WaaSMedicSvc";  DefaultStart = 3 }   # Manual (Demand)
    @{ Name = "bits";          DefaultStart = 2 }   # Delayed-Auto
    @{ Name = "dosvc";         DefaultStart = 2 }   # Delayed-Auto
    @{ Name = "uhssvc";        DefaultStart = 3 }   # Manual (Demand)
)

# ─── Scheduled Tasks to manage ───────────────────────────────────────────────
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
)

# ─── Firewall rules ──────────────────────────────────────────────────────────
$firewallRules = @(
    @{ Name = "winDOHs Block wuauclt";          Program = "$env:SystemRoot\System32\wuauclt.exe" }
    @{ Name = "winDOHs Block WaaSMedic";        Program = "$env:SystemRoot\System32\WaaSMedicAgent.exe" }
    @{ Name = "winDOHs Block UsoClient";        Program = "$env:SystemRoot\System32\UsoClient.exe" }
    @{ Name = "winDOHs Block musNotify";        Program = "$env:SystemRoot\System32\musNotification.exe" }
    @{ Name = "winDOHs Block musNotifyWorker";  Program = "$env:SystemRoot\System32\musNotificationUx.exe" }
)

# ─── Group Policy registry values ────────────────────────────────────────────
$gpKeyAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$gpKeyWU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# ===========================================================================
#  INSTALL — Disable & block all Windows Updates
# ===========================================================================
function Invoke-Install {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   DISABLING ALL WINDOWS UPDATES..." -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    # ── 1. Stop services ────────────────────────────────────────────────────
    Write-Host "  [1/8] Stopping Windows Update services..." -ForegroundColor Yellow
    foreach ($svc in $updateServices) {
        Stop-ServiceSafe -Name $svc.Name
    }

    # ── 2. Disable services ─────────────────────────────────────────────────
    Write-Host "  [2/8] Disabling Windows Update services..." -ForegroundColor Yellow
    foreach ($svc in $updateServices) {
        Set-ServiceStartupType -Name $svc.Name -StartType 4  # 4 = Disabled
    }

    # ── 3. Lock WaaSMedicSvc ────────────────────────────────────────────────
    Write-Host "  [3/8] Locking WaaSMedicSvc from self-healing..." -ForegroundColor Yellow
    $waasMedicReg = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
    if (Test-Path $waasMedicReg) {
        Set-ItemProperty -Path $waasMedicReg -Name "Start" -Value 4 -ErrorAction SilentlyContinue
        # Null out failure actions so Windows can't auto-restart
        $failBytes = [byte[]](0,0,0,0, 0,0,0,0, 0,0,0,0, 3,0,0,0, 20,0,0,0,
                              0,0,0,0, 0x60,0xEA,0,0, 0,0,0,0, 0x60,0xEA,0,0,
                              0,0,0,0, 0x60,0xEA,0,0)
        Set-ItemProperty -Path $waasMedicReg -Name "FailureActions" -Value $failBytes -ErrorAction SilentlyContinue
    }

    # ── 4. Group Policy registry ────────────────────────────────────────────
    Write-Host "  [4/8] Applying Group Policy registry keys..." -ForegroundColor Yellow
    if (-not (Test-Path $gpKeyAU)) { New-Item -Path $gpKeyAU -Force | Out-Null }
    if (-not (Test-Path $gpKeyWU)) { New-Item -Path $gpKeyWU -Force | Out-Null }

    Set-ItemProperty -Path $gpKeyAU -Name "NoAutoUpdate"                            -Value 1 -Type DWord
    Set-ItemProperty -Path $gpKeyAU -Name "AUOptions"                               -Value 1 -Type DWord
    Set-ItemProperty -Path $gpKeyWU -Name "DoNotConnectToWindowsUpdateInternetLocations" -Value 1 -Type DWord
    Set-ItemProperty -Path $gpKeyWU -Name "DisableWindowsUpdateAccess"              -Value 1 -Type DWord
    Set-ItemProperty -Path $gpKeyWU -Name "SetDisableUXWUAccess"                    -Value 1 -Type DWord
    Set-ItemProperty -Path $gpKeyWU -Name "ExcludeWUDriversInQualityUpdate"         -Value 1 -Type DWord
    Set-ItemProperty -Path $gpKeyWU -Name "SetPolicyDrivenUpdateSourceForFeatureUpdates"  -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $gpKeyWU -Name "SetPolicyDrivenUpdateSourceForQualityUpdates"  -Value 1 -Type DWord -ErrorAction SilentlyContinue

    # ── 5. Disable Scheduled Tasks ──────────────────────────────────────────
    Write-Host "  [5/8] Disabling Windows Update scheduled tasks..." -ForegroundColor Yellow
    foreach ($task in $updateTasks) {
        try {
            Disable-ScheduledTask -TaskName (Split-Path $task -Leaf) -TaskPath (Split-Path $task -Parent) -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }

    # ── 6. Block domains in HOSTS ───────────────────────────────────────────
    Write-Host "  [6/8] Blocking Windows Update servers in HOSTS file..." -ForegroundColor Yellow
    $hostsContent = Get-Content -Path $hostsPath -Raw -ErrorAction SilentlyContinue
    if ($hostsContent -notmatch [regex]::Escape($blockStart)) {
        $entries  = "`r`n$blockStart`r`n"
        foreach ($domain in $updateDomains) {
            $entries += "0.0.0.0 $domain`r`n"
        }
        $entries += "$blockEnd`r`n"
        Add-Content -Path $hostsPath -Value $entries -Encoding ASCII
    }

    # ── 7. Rename SoftwareDistribution ──────────────────────────────────────
    Write-Host "  [7/8] Renaming SoftwareDistribution folder..." -ForegroundColor Yellow
    $sdPath    = "$env:SystemRoot\SoftwareDistribution"
    $sdBackup  = "$env:SystemRoot\SoftwareDistribution.bak"
    if (Test-Path $sdPath) {
        Rename-Item -Path $sdPath -NewName "SoftwareDistribution.bak" -Force -ErrorAction SilentlyContinue
    }

    # ── 8. Firewall rules ──────────────────────────────────────────────────
    Write-Host "  [8/8] Adding firewall rules to block update binaries..." -ForegroundColor Yellow
    foreach ($rule in $firewallRules) {
        try {
            $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            if (-not $existing) {
                New-NetFirewallRule -DisplayName $rule.Name -Direction Outbound -Action Block `
                    -Program $rule.Program -Enabled True -Profile Any -ErrorAction SilentlyContinue | Out-Null
            }
        } catch { }
    }

    # ── 9. Take ownership of UsoClient.exe and revoke execute ──────────────
    Write-Host "  [BONUS] Revoking execute permissions on UsoClient.exe..." -ForegroundColor Yellow
    $usoPath = "$env:SystemRoot\System32\UsoClient.exe"
    if (Test-Path $usoPath) {
        & takeown /f $usoPath /a 2>$null | Out-Null
        & icacls $usoPath /deny "Everyone:(RX)" 2>$null | Out-Null
    }

    # Flush DNS
    ipconfig /flushdns 2>$null | Out-Null

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host "   ALL DONE - Windows Update has been DISABLED." -ForegroundColor Green
    Write-Host "   A reboot is recommended to fully apply changes." -ForegroundColor Green
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host ""
}

# ===========================================================================
#  REVERT — Re-enable Windows Updates
# ===========================================================================
function Invoke-Revert {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   RE-ENABLING WINDOWS UPDATES..." -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    # ── 1. Re-enable services ───────────────────────────────────────────────
    Write-Host "  [1/8] Re-enabling Windows Update services..." -ForegroundColor Yellow
    foreach ($svc in $updateServices) {
        Set-ServiceStartupType -Name $svc.Name -StartType $svc.DefaultStart
    }

    # ── 2. Start services ──────────────────────────────────────────────────
    Write-Host "  [2/8] Starting Windows Update services..." -ForegroundColor Yellow
    foreach ($svc in @("bits", "wuauserv", "UsoSvc", "dosvc")) {
        Start-ServiceSafe -Name $svc
    }

    # ── 3. Restore WaaSMedicSvc ─────────────────────────────────────────────
    Write-Host "  [3/8] Restoring WaaSMedicSvc defaults..." -ForegroundColor Yellow
    $waasMedicReg = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
    if (Test-Path $waasMedicReg) {
        Set-ItemProperty -Path $waasMedicReg -Name "Start" -Value 3 -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $waasMedicReg -Name "FailureActions" -ErrorAction SilentlyContinue
    }

    # ── 4. Remove Group Policy keys ─────────────────────────────────────────
    Write-Host "  [4/8] Removing Group Policy registry keys..." -ForegroundColor Yellow
    $valuesToRemove = @(
        @{ Path = $gpKeyAU; Name = "NoAutoUpdate" },
        @{ Path = $gpKeyAU; Name = "AUOptions" },
        @{ Path = $gpKeyWU; Name = "DoNotConnectToWindowsUpdateInternetLocations" },
        @{ Path = $gpKeyWU; Name = "DisableWindowsUpdateAccess" },
        @{ Path = $gpKeyWU; Name = "SetDisableUXWUAccess" },
        @{ Path = $gpKeyWU; Name = "ExcludeWUDriversInQualityUpdate" },
        @{ Path = $gpKeyWU; Name = "SetPolicyDrivenUpdateSourceForFeatureUpdates" },
        @{ Path = $gpKeyWU; Name = "SetPolicyDrivenUpdateSourceForQualityUpdates" }
    )
    foreach ($val in $valuesToRemove) {
        if (Test-Path $val.Path) {
            Remove-ItemProperty -Path $val.Path -Name $val.Name -ErrorAction SilentlyContinue
        }
    }

    # ── 5. Re-enable Scheduled Tasks ────────────────────────────────────────
    Write-Host "  [5/8] Re-enabling Windows Update scheduled tasks..." -ForegroundColor Yellow
    foreach ($task in $updateTasks) {
        try {
            Enable-ScheduledTask -TaskName (Split-Path $task -Leaf) -TaskPath (Split-Path $task -Parent) -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }

    # ── 6. Remove HOSTS blocks ──────────────────────────────────────────────
    Write-Host "  [6/8] Removing HOSTS file blocks..." -ForegroundColor Yellow
    if (Test-Path $hostsPath) {
        $lines   = Get-Content -Path $hostsPath
        $clean   = @()
        $skip    = $false
        foreach ($line in $lines) {
            if ($line -eq $blockStart) { $skip = $true; continue }
            if ($line -eq $blockEnd)   { $skip = $false; continue }
            if (-not $skip) { $clean += $line }
        }
        Set-Content -Path $hostsPath -Value $clean -Encoding ASCII
    }

    # ── 7. Restore SoftwareDistribution ─────────────────────────────────────
    Write-Host "  [7/8] Restoring SoftwareDistribution folder..." -ForegroundColor Yellow
    $sdBackup = "$env:SystemRoot\SoftwareDistribution.bak"
    if (Test-Path $sdBackup) {
        Rename-Item -Path $sdBackup -NewName "SoftwareDistribution" -Force -ErrorAction SilentlyContinue
    }

    # ── 8. Remove firewall rules ────────────────────────────────────────────
    Write-Host "  [8/8] Removing firewall block rules..." -ForegroundColor Yellow
    foreach ($rule in $firewallRules) {
        Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    }

    # ── 9. Restore UsoClient.exe permissions ────────────────────────────────
    Write-Host "  [BONUS] Restoring UsoClient.exe permissions..." -ForegroundColor Yellow
    $usoPath = "$env:SystemRoot\System32\UsoClient.exe"
    if (Test-Path $usoPath) {
        & icacls $usoPath /remove:d "Everyone" 2>$null | Out-Null
        & icacls $usoPath /grant "Everyone:(RX)" 2>$null | Out-Null
        & icacls $usoPath /setowner "NT SERVICE\TrustedInstaller" 2>$null | Out-Null
    }

    # Flush DNS
    ipconfig /flushdns 2>$null | Out-Null

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host "   ALL DONE - Windows Update has been RE-ENABLED." -ForegroundColor Green
    Write-Host "   A reboot is recommended to fully apply changes." -ForegroundColor Green
    Write-Host "  ============================================================" -ForegroundColor Green
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
        Write-Host "       winDOHs Update Disabler  -  PowerShell Edition" -ForegroundColor Cyan
        Write-Host "  ============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    [1] INSTALL  - Disable & Block ALL Windows Updates"
        Write-Host "    [2] REVERT   - Re-enable Windows Updates"
        Write-Host "    [3] EXIT"
        Write-Host ""
        $choice = Read-Host "  Select an option (1/2/3)"

        switch ($choice) {
            "1" { Invoke-Install; pause }
            "2" { Invoke-Revert;  pause }
            "3" { return }
        }
    } while ($true)
}
