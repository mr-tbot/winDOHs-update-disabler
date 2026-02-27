# Instructions

Complete usage guide for **winDOHs Update Disabler**.

---
 
## Prerequisites

- **Windows 10 or 11** (Home, Pro, Enterprise, or Education)
- **Administrator privileges** — both scripts will refuse to run without elevation
- **No third-party dependencies** — everything uses built-in Windows tools

---

## Option A — Batch Script (`DisableWindowsUpdate.bat`)

### Disable Windows Update

1. **Right-click** `DisableWindowsUpdate.bat` and select **Run as administrator**.
2. A console window will appear with a menu:
   ```
   [1] INSTALL  - Disable & Block ALL Windows Updates
   [2] REVERT   - Re-enable Windows Updates
   [3] EXIT
   ```
3. Type **`1`** and press **Enter**.
4. The script runs through 8 steps. When you see **"ALL DONE — Windows Update has been DISABLED"**, press any key.
5. **Reboot** your PC to fully apply all changes.

### Re-enable Windows Update

1. Run the same script as administrator.
2. Choose **`2`** (REVERT).
3. The script reverses every change made during install.
4. **Reboot** to complete restoration.

---

## Option B — PowerShell Script (`DisableWindowsUpdate.ps1`)

### Interactive Mode

1. Open **PowerShell as Administrator**:
   - Press `Win + X` → select **Windows Terminal (Admin)** or **PowerShell (Admin)**.
2. Navigate to the script folder:
   ```powershell
   cd "C:\path\to\winDOHs-update-disabler"
   ```
3. If needed, allow script execution for the current session:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
4. Run the script:
   ```powershell
   .\DisableWindowsUpdate.ps1
   ```
5. Choose **[1] INSTALL** or **[2] REVERT** from the menu.
6. **Reboot** after the script finishes.

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

### Step 1 — Stop & Disable Services

| Service | Display Name |
|---------|-------------|
| `wuauserv` | Windows Update |
| `UsoSvc` | Update Orchestrator Service |
| `WaaSMedicSvc` | Windows Update Medic Service |
| `bits` | Background Intelligent Transfer Service |
| `dosvc` | Delivery Optimization |
| `uhssvc` | Microsoft Update Health Service |

**Install:** Services are stopped and their startup type is set to **Disabled**.
**Revert:** Startup types are restored to their Windows defaults (Manual or Delayed-Auto) and services are started.

### Step 2 — Lock WaaSMedicSvc Self-Healing

Windows uses WaaSMedicSvc to automatically repair and restart update services. This step overwrites its `FailureActions` registry value so Windows cannot auto-restart it.

**Revert:** The registry value is removed, restoring normal recovery behaviour.

### Step 3 — Group Policy Registry Keys

The following values are written under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`:

| Value | Effect |
|-------|--------|
| `NoAutoUpdate = 1` | Disables automatic updates |
| `AUOptions = 1` | Keeps auto-update disabled |
| `DoNotConnectToWindowsUpdateInternetLocations = 1` | Blocks connections to update servers |
| `DisableWindowsUpdateAccess = 1` | Removes access to Windows Update |
| `SetDisableUXWUAccess = 1` | Hides the Windows Update UI |
| `ExcludeWUDriversInQualityUpdate = 1` | Prevents driver updates |

**Revert:** All values are deleted from the registry.

### Step 4 — Disable Scheduled Tasks

13 tasks across three paths are disabled:

- `\Microsoft\Windows\WindowsUpdate\*` (3 tasks)
- `\Microsoft\Windows\UpdateOrchestrator\*` (9 tasks)
- `\Microsoft\Windows\WaaSMedic\PerformRemediation`

**Revert:** All tasks are re-enabled.

### Step 5 — Block Update Domains via HOSTS File

16 Microsoft update domains are redirected to `0.0.0.0` in `%SystemRoot%\System32\drivers\etc\hosts`. Entries are wrapped in marker comments (`winDOHs-UPDATE-BLOCK-START` / `END`) for clean removal.

**Revert:** Everything between the markers is removed from the HOSTS file.

### Step 6 — Rename SoftwareDistribution Folder

The folder `%SystemRoot%\SoftwareDistribution` is renamed to `SoftwareDistribution.bak`, destroying the update cache.

**Revert:** The folder is renamed back to `SoftwareDistribution`.

### Step 7 — Outbound Firewall Rules

Outbound block rules are created for these executables:

| Rule Name | Blocked Program |
|-----------|----------------|
| winDOHs Block wuauclt | `wuauclt.exe` |
| winDOHs Block WaaSMedic | `WaaSMedicAgent.exe` |
| winDOHs Block UsoClient | `UsoClient.exe` |
| winDOHs Block musNotify | `musNotification.exe` |
| winDOHs Block musNotifyWorker | `musNotificationUx.exe` |

**Revert:** All five firewall rules are deleted.

### Step 8 — Revoke UsoClient.exe Permissions *(PowerShell only)*

`UsoClient.exe` is the binary Windows calls to trigger update scans. The PowerShell script takes ownership and denies Read/Execute to `Everyone`.

**Revert:** Permissions are restored and ownership is returned to `TrustedInstaller`.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **"This script must be run as Administrator"** | Right-click → **Run as administrator** |
| **PowerShell says "scripts are disabled"** | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first |
| **Updates still appear after install** | Reboot — some changes only take effect after restart |
| **A service keeps restarting** | Run the script again; WaaSMedic may have re-enabled services before reboot |
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
