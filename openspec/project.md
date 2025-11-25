# Project Context

## Purpose
PowerShell 7 tooling to audit Windows devices in Entra ID (Azure AD) and surface BitLocker and LAPS posture, Intune activity, and core device metadata. Primary output is an XML report (with optional CSV) plus a timestamped log for operational and security review.

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
- Logging: timestamped `WindowsAudit-YYYY-MM-DD-HH-MM.log`, `Write-Verbose`/`Write-Warning`/`Write-Error` mapped from `Write-Log` level
- Do not print secrets; only record existence/backup status for BitLocker/LAPS
- Pagination handled via `@odata.nextLink`; retries respect Graph throttling (`Retry-After`)
- Default runs with `-NoProfile`; allow `-SkipModuleImport` to rely on REST fallback when modules aren’t available

### Architecture Patterns
- Flow: authenticate (delegated or app-only) → enumerate Windows devices → enrich via Intune ManagedDevice → fetch BitLocker recovery keys (per-drive OS/Data) → fetch LAPS credential existence → emit XML/CSV → log every step
- App-only path can provision app + service principal + cert when `-CreateAppIfMissing` is set; certificate stored in `Cert:\CurrentUser\My`
- Error handling favors “continue on error”; 404s for BitLocker/LAPS treated as “not found” not fatal

### Testing Strategy
- Manual runs with scoped parameters: `-MaxDevices`, `-DeviceName` for spot checks; `-ExportCSV` for quick verification
- Validate XML against `Demo.xsd` using sample snippet in `README.md`
- `Test-LAPS.ps1` for targeted LAPS existence checks
- No automated test suite yet; manual validation plus log review

### Git Workflow
- Not explicitly defined in repo; default to feature branches with descriptive commits and PR review before merging to main
- Keep OpenSpec changes proposal-driven for new capabilities; small bug fixes can go direct

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
