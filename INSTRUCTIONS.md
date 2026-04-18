# Instructions

Complete usage guide for **winDOHs Update Disabler v2.0**.

---
 
## Prerequisites

- **Windows 10 or 11** (Home, Pro, Enterprise, or Education)
- **Administrator privileges** — both scripts auto-elevate via UAC if not already elevated
- **No third-party dependencies** — everything uses built-in Windows tools

---

## Option A — Batch Script (`DisableWindowsUpdate.bat`)

### Disable Windows Update

1. **Double-click** `DisableWindowsUpdate.bat` — it will request admin privileges via a UAC prompt.
2. A console window will appear with a menu:
   ```
   [1] INSTALL  - Disable & Block ALL Windows Updates
   [2] REVERT   - Re-enable Windows Updates
   [3] STATUS   - Check current block status
   [4] EXIT
   ```
3. Type **`1`** and press **Enter**.
4. The script runs through 12 steps. When you see **"ALL DONE — Windows Update has been DISABLED (12 layers)"**, press any key.
5. **Reboot** your PC to fully apply all changes.

### Re-enable Windows Update

1. Run the same script (it will auto-elevate).
2. Choose **`2`** (REVERT).
3. The script reverses every change made during install (unlocks ACLs, restores services, removes hosts blocks, etc.).
4. **Reboot** to complete restoration.

### Check Status

1. Run the same script.
2. Choose **`3`** (STATUS).
3. A colour-coded report shows green (blocked) or red (not blocked) for every protection layer.

---

## Option B — PowerShell Script (`DisableWindowsUpdate.ps1`)

### Interactive Mode

1. **Double-click** `DisableWindowsUpdate.ps1` — it will auto-elevate via UAC prompt.
   - Alternatively, open **PowerShell as Administrator** and run:
   ```powershell
   cd "C:\path\to\winDOHs-update-disabler"
   .\DisableWindowsUpdate.ps1
   ```
2. Choose **[1] INSTALL**, **[2] REVERT**, or **[3] STATUS** from the menu.
3. **Reboot** after install or revert.

### Silent / Scripted Mode

You can skip the interactive menu by passing the `-Mode` parameter:

```powershell
# Disable updates
.\DisableWindowsUpdate.ps1 -Mode Install

# Re-enable updates
.\DisableWindowsUpdate.ps1 -Mode Revert
```

This is useful for deployment scripts, remote management, or automation.

---

## What Each Step Does

Below is a breakdown of every layer applied during **INSTALL** and what **REVERT** does to undo it.

### Step 1 — Stop Services

| Service | Display Name |
|---------|-------------|
| `wuauserv` | Windows Update |
| `UsoSvc` | Update Orchestrator Service |
| `WaaSMedicSvc` | Windows Update Medic Service |
| `bits` | Background Intelligent Transfer Service |
| `dosvc` | Delivery Optimization |
| `uhssvc` | Microsoft Update Health Service |
| `sedsvc` | Windows Remediation Service |

**Install:** All 7 services are stopped.
**Revert:** Services `bits`, `wuauserv`, `UsoSvc`, and `dosvc` are started.

### Step 2 — Disable Services & Null Recovery Actions

**Install:** All 7 services are set to **Disabled** (`Start = 4`). The `FailureActions` registry value for every service is overwritten with "do nothing" actions, preventing Windows from auto-restarting them on failure.
**Revert:** Startup types are restored to Windows defaults (`Manual` for most, `Automatic (Delayed Start)` for `bits` and `dosvc`). `FailureActions` values are removed.

### Step 3 — ACL-Lock Service Registry Keys (Anti-Tamper)

The three critical services (`wuauserv`, `UsoSvc`, `WaaSMedicSvc`) have their registry keys locked with Access Control Lists:
- **Administrators** get Full Control
- **SYSTEM** gets Read-only access
- **SYSTEM** is DENIED `SetValue`, `CreateSubKey`, and `Delete`

This is the #1 defence against WaaSMedic self-healing — it physically cannot write the `Start` value back.

Uses **SecurityIdentifier-based enumeration** to avoid crashes from orphaned SIDs in the registry.

**Revert:** Deny rules are removed, SYSTEM gets Full Control restored, and inheritance is re-enabled.

### Step 4 — Group Policy Registry Keys

The following values are written under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` (and `\AU`):

| Value | Effect |
|-------|--------|
| `NoAutoUpdate = 1` | Disables automatic updates |
| `AUOptions = 1` | Keeps auto-update disabled |
| `DoNotConnectToWindowsUpdateInternetLocations = 1` | Blocks connections to update servers |
| `DisableWindowsUpdateAccess = 1` | Removes access to Windows Update |
| `SetDisableUXWUAccess = 1` | Hides the Windows Update UI |
| `ExcludeWUDriversInQualityUpdate = 1` | Prevents driver updates |
| `SetPolicyDrivenUpdateSourceForFeatureUpdates = 1` | Blocks feature update source |
| `SetPolicyDrivenUpdateSourceForQualityUpdates = 1` | Blocks quality update source |
| `DisableOSUpgrade = 1` | Prevents OS upgrades |
| `ManagePreviewBuildsPolicyValue = 1` | Blocks preview/insider builds |

**Revert:** All values are deleted (including `TargetReleaseVersion` and `TargetReleaseVersionInfo`).

### Step 5 — Additional Registry Hardening

| Key | Value | Effect |
|-----|-------|--------|
| `Schedule\Maintenance` | `MaintenanceDisabled = 1` | Stops automatic maintenance (triggers update scans) |
| `WindowsStore` | `AutoDownload = 2` | Disables Store auto-updates |
| `OSUpgrade` | `AllowOSUpgrade = 0` | Blocks OS upgrade via alternate codepath |
| `WindowsUpdate` | `TargetReleaseVersion = 1` | Enables version lock |
| `WindowsUpdate` | `TargetReleaseVersionInfo = <current>` | Locks to your current OS version (e.g. `23H2`) |

After writing values, the script **ACL-locks 3 Group Policy registry keys** (`WindowsUpdate`, `WindowsUpdate\AU`, `WindowsStore`) with the same DENY-SYSTEM-write pattern used for service keys. This prevents the OS from reverting GP values.

**Revert:** GP key ACLs are unlocked first, then all additional values are deleted.

### Step 6 — Disable Scheduled Tasks

20 tasks across three paths are disabled:

- `\Microsoft\Windows\WindowsUpdate\*` — `Scheduled Start`, `sih`, `sihboot`
- `\Microsoft\Windows\UpdateOrchestrator\*` — `Schedule Scan`, `Schedule Scan Static Task`, `UpdateModelTask`, `USO_UxBroker`, `Schedule Work`, `Schedule Wake To Work`, `Reboot_AC`, `Reboot_Battery`, `Report policies`, `Backup Scan`, `Schedule Maintenance Work`, `Universal Orchestrator Start`, `Universal Orchestrator Idle`, `UUS Failover Task`, `policyupdate`, `Start Oobe Expedite Work`
- `\Microsoft\Windows\WaaSMedic\PerformRemediation`

**Revert:** All 20 tasks are re-enabled.

### Step 7 — Block Update Domains via HOSTS File

30 Microsoft update domains are redirected to `0.0.0.0` in the system HOSTS file. Entries are wrapped in marker comments (`winDOHs-UPDATE-BLOCK-START` / `END`) for clean removal.

The script **stops the DNS Client service (Dnscache)** before writing to avoid file-lock failures, then restarts it after.

**Revert:** Everything between the markers is removed. Dnscache is stopped/restarted during the write.

### Step 8 — Rename SoftwareDistribution Folder

The folder `%SystemRoot%\SoftwareDistribution` is renamed to `SoftwareDistribution.bak`, destroying the update cache.

**Revert:** The folder is renamed back to `SoftwareDistribution`.

### Step 9 — Outbound Firewall Rules

Outbound block rules are created for 7 executables:

| Rule Name | Blocked Program |
|-----------|----------------|
| winDOHs Block wuauclt | `wuauclt.exe` |
| winDOHs Block WaaSMedic | `WaaSMedicAgent.exe` |
| winDOHs Block UsoClient | `UsoClient.exe` |
| winDOHs Block musNotify | `musNotification.exe` |
| winDOHs Block musNotifyWorker | `musNotificationUx.exe` |
| winDOHs Block UpdateAssist | `UpdateAssistant.exe` |
| winDOHs Block sedLauncher | `sedlauncher.exe` |

**Revert:** All 7 firewall rules are deleted.

### Step 10 — Revoke Execute Permissions on Update Binaries

6 binaries have their execute permissions denied via `takeown` + `icacls /deny Everyone:(RX)`:

`UsoClient.exe`, `WaaSMedicAgent.exe`, `wuauclt.exe`, `musNotification.exe`, `musNotificationUx.exe`, `sedlauncher.exe`

**Revert:** Deny rules are removed, Read/Execute is granted, ownership is returned to `TrustedInstaller`.

### Step 11 — Windows Update Assistant Cleanup

If `%SystemRoot%\UpdateAssistant` exists, the script takes ownership and denies execute permissions to prevent the Update Assistant from running.

**Revert:** Permissions are restored and ownership is returned to `TrustedInstaller`.

### Step 12 — Flush DNS Cache

`ipconfig /flushdns` is run to clear any cached DNS entries for the blocked update domains.

---

## Status Checker

Both scripts include a **[3] STATUS** option that checks every protection layer and displays a colour-coded report:

- **Green** = blocked / locked / present (protection active)
- **Red** = not blocked / unlocked / missing (potential leak)

Checks include:
- All 7 services (status + startup type)
- Service registry ACL lockdown (3 keys)
- Group Policy ACL lockdown (3 keys)
- Group Policy values (4 key values)
- Additional registry values (maintenance, Store)
- HOSTS file block markers
- Firewall rules (all 7)
- SoftwareDistribution folder state
- Binary execute permissions (all 6)

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **UAC prompt doesn't appear** | Right-click → **Run as administrator** manually |
| **PowerShell says "scripts are disabled"** | The script auto-elevates with `-ExecutionPolicy Bypass`. If running manually: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| **Updates still appear after install** | Reboot — some changes only take effect after restart |
| **A service keeps restarting** | Run STATUS to check — the ACL lockdown should prevent this. If still occurring, run INSTALL again |
| **HOSTS file write fails** | The script stops Dnscache automatically. If it still fails, ensure no other program (e.g. antivirus) is locking the file |
| **Registry writes fail (red warnings)** | Check that your user account has admin rights. The script verifies each write with a readback |
| **Want to undo everything** | Run the same script and choose **REVERT**, then reboot |
| **HOSTS file looks wrong after revert** | Open `%SystemRoot%\System32\drivers\etc\hosts` in Notepad (admin) and remove any leftover `0.0.0.0` lines manually |

---

## FAQ

**Q: Will this break other Microsoft services (Office, Teams, Store)?**
A: The HOSTS blocks target update-specific domains. `download.microsoft.com` and `go.microsoft.com` are general-purpose, so blocking them *may* affect other downloads. If that's a concern, you can manually remove those two lines from your HOSTS file after running the script.

**Q: Can I run the script on multiple PCs?**
A: Yes. The PowerShell script supports `-Mode Install` for silent deployment — ideal for use with remote management tools or login scripts.

**Q: Is a reboot really necessary?**
A: Strongly recommended. Some services and scheduled tasks may still be in memory until the next restart.

**Q: Are the BAT and PS1 scripts identical in function?**
A: Yes. As of v2.0, both scripts apply the exact same 12 layers of protection with the same hardening. The only difference is the PS1 supports a `-Mode` parameter for scripted use and has a readback-verified registry write function.
