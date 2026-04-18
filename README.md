# winDOHs Update Disabler v2.0

**Take back control of your Windows PC.** This toolkit fully disables — or re-enables — Windows Update using **12 independent, layered methods** so the OS cannot silently undo your choice.

Available as both a classic **Batch (.bat)** script and a **PowerShell (.ps1)** script. Both are functionally identical — pick whichever you prefer.

---

## What It Does

| Layer | Action |
|------:|--------|
| 1 | **Stop** all update-related services (`wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `BITS`, `dosvc`, `uhssvc`, `sedsvc`) |
| 2 | **Disable** all services & **null out recovery/failure actions** for every service |
| 3 | **ACL-lock service registry keys** — DENY SYSTEM write access to prevent WaaSMedic self-healing |
| 4 | **Group Policy registry keys** — `NoAutoUpdate`, `DisableWindowsUpdateAccess`, block drivers, OS upgrade lock, preview builds, and more (10 values) |
| 5 | **Additional registry hardening** — disable maintenance, Store auto-updates, OS upgrade codepath, lock to current OS version, **ACL-lock GP keys** against SYSTEM writes |
| 6 | **Disable 20 scheduled tasks** under `WindowsUpdate`, `UpdateOrchestrator`, and `WaaSMedic` |
| 7 | **Block 30 update domains** in the HOSTS file (`0.0.0.0`) with DNS client lock handling |
| 8 | **Rename** `SoftwareDistribution` folder to nuke the update cache |
| 9 | **Outbound firewall rules** blocking 7 update binaries (`wuauclt`, `WaaSMedic`, `UsoClient`, `musNotify`, `musNotifyWorker`, `UpdateAssist`, `sedLauncher`) |
| 10 | **Revoke execute permissions** on all 6 update binaries via `takeown` + `icacls` |
| 11 | **Lock down Windows Update Assistant** directory |
| 12 | **Flush DNS cache** |

Every layer can be **fully reverted** with a single click/command.

---

## Quick Start

1. Download or clone this repository.
2. **Double-click** `DisableWindowsUpdate.bat` (or `.ps1`) — it will auto-elevate via UAC prompt.
3. Choose **[1] INSTALL** to disable updates, **[2] REVERT** to re-enable, or **[3] STATUS** to check.
4. Reboot to fully apply changes.

> For detailed step-by-step instructions see [INSTRUCTIONS.md](INSTRUCTIONS.md).

---

## Files

| File | Description |
|------|-------------|
| `DisableWindowsUpdate.bat` | Batch script — works on any Windows version, auto-elevates via UAC |
| `DisableWindowsUpdate.ps1` | PowerShell script — supports `-Mode Install`/`Revert` for silent/scripted use, auto-elevates via UAC |
| `INSTRUCTIONS.md` | Full usage guide with prerequisites, walkthroughs, and troubleshooting |

---

## Compatibility

- **Windows 10** (all editions)
- **Windows 11** (all editions)
- Requires **Administrator** privileges (scripts auto-elevate via UAC if not already elevated)

---

## Changelog

### v2.0

- **12 protection layers** (up from 8) — added ACL lockdown, binary permissions, Update Assistant, and more
- **Auto-elevation** — scripts now request admin via UAC prompt instead of failing with an error
- **Status checker** — new `[3] STATUS` menu option shows green/red status of every protection layer
- **ACL lockdown on service registry keys** — DENY SYSTEM write access on `wuauserv`, `UsoSvc`, `WaaSMedicSvc` to prevent WaaSMedic self-healing
- **ACL lockdown on Group Policy registry keys** — prevents SYSTEM from reverting GP values at `WindowsUpdate`, `WindowsUpdate\AU`, and `WindowsStore`
- **Null failure/recovery actions** for all 7 services (not just WaaSMedic)
- **SecurityIdentifier-based ACL enumeration** — fixes crashes from orphaned SIDs in registry ACLs
- **DNS client (Dnscache) lock handling** — stops/restarts Dnscache before writing HOSTS file to prevent file-locked failures
- **30 blocked domains** (up from 16) — expanded with CDN, telemetry, and alternate update endpoints
- **20 disabled scheduled tasks** (up from 13) — added Backup Scan, Maintenance Work, Universal Orchestrator, UUS Failover, policyupdate, Oobe Expedite
- **7 firewall rules** (up from 5) — added `UpdateAssistant.exe` and `sedlauncher.exe`
- **6 binary execute denials** (up from 1) — `UsoClient`, `WaaSMedic`, `wuauclt`, `musNotification`, `musNotificationUx`, `sedlauncher`
- **Windows Update Assistant** directory lockdown (install) and restore (revert)
- **`sedsvc`** (Windows Remediation Service) added to managed services
- **OS version lock** — `TargetReleaseVersion` + `TargetReleaseVersionInfo` prevent feature updates
- **Store auto-download disabled** and **automatic maintenance disabled**
- **Delayed-auto start** correctly restored for `bits`/`dosvc` on revert
- **BAT and PS1 are now fully 1:1** in functionality across all 12 layers

### v1.0

- Initial release with 8 protection layers
- Batch and PowerShell editions

---

## Disclaimer

> **Use at your own risk.** Disabling Windows Update means you will not receive security patches, driver updates, or feature updates until you re-enable it. This tool is intended for advanced users who understand the trade-offs.

---

## License

This project is provided as-is with no warranty. Free to use, modify, and distribute.
