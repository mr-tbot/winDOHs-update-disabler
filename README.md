# winDOHs Update Disabler

**Take back control of your Windows PC.** This toolkit fully disables — or re-enables — Windows Update using **8 independent, layered methods** so the OS cannot silently undo your choice.

Available as both a classic **Batch (.bat)** script and a **PowerShell (.ps1)** script. Pick whichever you prefer; they do the same thing.

---

## What It Does 

| Layer | Action |
|------:|--------|
| 1 | **Stop & disable** all update-related services (`wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `BITS`, `dosvc`, `uhssvc`) |
| 2 | **Lock WaaSMedicSvc** — prevents Windows from self-healing the update service |
| 3 | **Group Policy registry keys** — `NoAutoUpdate`, `DisableWindowsUpdateAccess`, block driver updates, etc. |
| 4 | **Disable 13 scheduled tasks** under `WindowsUpdate`, `UpdateOrchestrator`, and `WaaSMedic` |
| 5 | **Block update domains** in the HOSTS file (16 Microsoft domains → `0.0.0.0`) |
| 6 | **Rename** `SoftwareDistribution` folder to nuke the update cache |
| 7 | **Outbound firewall rules** blocking `wuauclt.exe`, `WaaSMedicAgent.exe`, `UsoClient.exe`, `musNotification.exe`, `musNotificationUx.exe` |
| 8 | *(PowerShell only)* **Revoke execute permissions** on `UsoClient.exe` via `takeown` + `icacls` |

Every layer can be **fully reverted** with a single click/command.

---

## Quick Start

1. Download or clone this repository.
2. Right-click **`DisableWindowsUpdate.bat`** (or `.ps1`) → **Run as administrator**.
3. Choose **[1] INSTALL** to disable updates, or **[2] REVERT** to re-enable them.
4. Reboot to fully apply changes.

> For detailed step-by-step instructions see [INSTRUCTIONS.md](INSTRUCTIONS.md).

---

## Files

| File | Description |
|------|-------------|
| `DisableWindowsUpdate.bat` | Batch script — works on any Windows version, no PowerShell needed |
| `DisableWindowsUpdate.ps1` | PowerShell script — supports a `-Mode` parameter for silent/scripted use |
| `INSTRUCTIONS.md` | Full usage guide with prerequisites, screenshots-style walkthroughs, and troubleshooting |

---

## Compatibility

- **Windows 10** (all editions)
- **Windows 11** (all editions)
- Requires **Administrator** privileges

---

## Disclaimer

> **Use at your own risk.** Disabling Windows Update means you will not receive security patches, driver updates, or feature updates until you re-enable it. This tool is intended for advanced users who understand the trade-offs.

---

## License

This project is provided as-is with no warranty. Free to use, modify, and distribute.
