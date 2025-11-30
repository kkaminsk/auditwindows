# Project Context

## Purpose
PowerShell 7 tooling to audit Windows devices in Entra ID (Azure AD) and surface BitLocker and LAPS posture, Intune activity, and core device metadata. Primary output is an XML report (with optional CSV) plus a timestamped log for operational and security review.

**Current Version:** 1.2 (2025-11-26)

**Author:** Kevin Kaminski
**License:** MIT
**Repository:** https://github.com/kkaminsk/auditwindows

## Tech Stack
- PowerShell 7 (`#Requires -Version 7.0`)
- Microsoft Graph PowerShell SDK (targeted submodules: Authentication, Identity.DirectoryManagement, DeviceManagement; Applications/ServicePrincipals only when provisioning app-only auth; InformationProtection when available)
- Graph REST fallback via `Invoke-MgGraphRequest` to avoid module/assembly issues
- Outputs: XML (validated by `Demo.xsd`) and optional CSV; structured text logs
- Runtime deps: Entra ID + Intune graph endpoints, Windows cert store for app-only auth certs

## Project Conventions

### Code Style
- Two-space indentation, `CmdletBinding()` with explicit `param` attributes/defaults
- Prefer focused helper functions (e.g., `Write-Log`, `Invoke-GraphGetAll`, `Import-GraphModuleIfNeeded`) and clear variable names
- All helper functions organized in `.\functions\` directory, loaded via dot-sourcing at script start
- Logging: timestamped `WindowsAudit-YYYY-MM-DD-HH-MM.log`, `Write-Verbose`/`Write-Warning`/`Write-Error` mapped from `Write-Log` level
- Do not print secrets; only record existence/backup status for BitLocker/LAPS
- Pagination handled via `@odata.nextLink`; retries respect Graph throttling (`Retry-After`)
- Default runs with `-NoProfile`; allow `-SkipModuleImport` to rely on REST fallback when modules aren't available
- Each function has companion `.md` documentation in `functions/` folder

### Architecture Patterns
- Flow: authenticate (delegated or app-only) → enumerate Windows devices → enrich via Intune ManagedDevice → fetch BitLocker recovery keys (per-drive OS/Data) → fetch LAPS credential existence → emit XML/CSV → log every step
- **Two authentication modes:**
  - **Delegated (interactive):** Default mode using "Audit Windows" app registration (setup via `Setup-AuditWindowsApp.ps1`)
  - **App-only (certificate):** Certificate-based auth for automation/unattended scenarios (`-UseAppAuth` flag)
- App-only path can provision app + service principal + cert when `-CreateAppIfMissing` is set; certificate stored in `Cert:\CurrentUser\My`
- Error handling favors "continue on error"; 404s for BitLocker/LAPS treated as "not found" not fatal
- Device filtering supported via `-DeviceName` (single device) or `-MaxDevices` (limit count)

### Testing Strategy
- Manual runs with scoped parameters: `-MaxDevices`, `-DeviceName` for spot checks; `-ExportCSV` for quick verification
- Validate XML against `Demo.xsd` using sample snippet in `README.md`
- `Test-LAPS.ps1` for targeted LAPS existence checks
- No automated test suite yet; manual validation plus log review

### Git Workflow
- Not explicitly defined in repo; default to feature branches with descriptive commits and PR review before merging to main
- Keep OpenSpec changes proposal-driven for new capabilities; small bug fixes can go direct

### File Structure
- `Get-EntraWindowsDevices.ps1` - Main audit script (execution)
- `Setup-AuditWindowsApp.ps1` - App registration setup script (one-time provisioning)
- `functions/` - Helper function library (25+ functions with individual .md docs)
- `openspec/` - OpenSpec change proposals and project documentation
- `executionflow/` - Execution flow diagrams for main scripts
- `Demo.xsd` - XML schema for audit report validation
- Output files (default: `%USERPROFILE%\Documents`):
  - `WindowsAudit-YYYY-MM-DD-HH-MM.log` - Structured log
  - `WindowsAudit-YYYY-MM-DD-HH-MM.xml` - Primary audit report
  - `WindowsAudit-YYYY-MM-DD-HH-MM.csv` - Optional CSV export

## Domain Context
Audits Entra ID Windows devices (including Intune-managed) for security posture: BitLocker recovery key backup presence (per OS/Data drive) and LAPS password availability, plus device metadata (Enabled, UPN, MDM, activity, last check-in).

## Important Constraints
- Requires Graph delegated scopes: Device.Read.All, BitLockerKey.ReadBasic.All, DeviceLocalCredential.ReadBasic.All, DeviceManagementManagedDevices.Read.All
- App-only requires equivalent application permissions; provisioning demands admin consent; certificate handling must stay secure
- Network access to Microsoft Graph is required; tool is read-only aside from optional app provisioning
- Avoid exposing secrets; only report existence/backup status
- Default output path is `%USERPROFILE%\Documents` unless overridden

## External Dependencies
- Microsoft Graph service endpoints: devices, managedDevices, informationProtection/bitlocker/recoveryKeys, devices/{id}/localCredentials
- Microsoft Graph PowerShell modules listed above (auto-installed when permitted)
- Windows certificate store (CurrentUser\My) for app-only authentication certificates
- Optional: XML validation via `Demo.xsd`

## Key Features
- **Dual auth modes:** Interactive delegated or unattended certificate-based
- **Dedicated app registration:** Custom branded "Audit Windows" app with granular permissions and conditional access support
- **BitLocker per-drive analysis:** Separate OS and Data drive encryption status
- **LAPS credential tracking:** Existence and retrieval status (no secrets exposed)
- **Intune enrichment:** LastCheckIn, Activity, UPN from managed devices
- **REST fallback:** `-SkipModuleImport` to avoid module/assembly conflicts
- **Comprehensive logging:** Timestamped structured logs with DEBUG/INFO/WARN/ERROR levels
- **XML schema validation:** XSD-based validation for audit reports
- **Progress tracking:** Per-device progress bars and verbose output
- **GPT assistance:** Custom ChatGPT bot available for interpreting results (paid account required for data privacy): https://chatgpt.com/g/g-68e6e364e48c8191993f38b9a190af02

## Roadmap
- Defender for Endpoint status integration
- Compliance policy status (Intune)
- Richer ManagedDevice fields
- Optional HTML report
- Package as PowerShell module
- Key Vault storage for certificates/private keys
- Managed identity support where feasible
