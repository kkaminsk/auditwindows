# auditwindows
Windows Audit Application (PowerShell 7) to inventory Windows devices from Entra ID via Microsoft Graph and report BitLocker and LAPS posture.

## Version

1.0 (2025-10-08)

## Author

Kevin Kaminski

## License

MIT

## Notes

Use the following chatgpt chatbot to understand how to use the tool or interpret your results: ***Make sure to use a paid account for data privacy***

https://chatgpt.com/g/g-68e6e364e48c8191993f38b9a190af02



## Overview

`Get-EntraWindowsDevices.ps1` connects to Microsoft Graph using either delegated (interactive) or app-only (certificate) auth to enumerate Entra ID devices with operatingSystem = "Windows", enriches with Intune ManagedDevice info (last check-in), evaluates BitLocker key backup presence (and emits a per-drive `Encrypted` flag), checks LAPS credential availability, and writes results to an XML report with optional CSV summary. The script can also fall back to direct REST calls via `Invoke-MgGraphRequest` when Graph cmdlets are unavailable. All actions are logged to a timestamped log.

## Prerequisites

- PowerShell 7+ (pwsh)
- Internet access to Microsoft Graph
- Microsoft Graph PowerShell SDK. The script auto-installs targeted Microsoft.Graph submodules (Authentication, Identity.DirectoryManagement, DeviceManagement, InformationProtection) and can skip imports with `-SkipModuleImport` to rely on REST fallback (`Invoke-MgGraphRequest`) and avoid assembly-load conflicts. App provisioning modules (Applications, ServicePrincipals) are only imported when `-UseAppAuth`/`-CreateAppIfMissing` are used.

## Permissions and Roles

Delegated Microsoft Graph scopes requested interactively:

- Device.Read.All
- BitLockerKey.Read.All
- Directory.Read.All
- DeviceLocalCredential.Read.All
- DeviceManagementManagedDevices.Read.All (required to populate LastCheckIn/Activity via Intune)

Application (app-only) permissions required when using `-UseAppAuth`:

- Device.Read.All
- Directory.Read.All
- BitLockerKey.Read.All
- DeviceLocalCredential.Read.All
- DeviceManagementManagedDevices.Read.All

Provisioning (admin-consent) scopes used when `-CreateAppIfMissing` is specified:

- Application.ReadWrite.All
- AppRoleAssignment.ReadWrite.All
- Directory.ReadWrite.All

Recommended Azure roles (any one that covers the above):

- Global Reader
- Intune Administrator
- Security Reader

Note: If `DeviceManagementManagedDevices.Read.All` isn’t granted, Intune enrichment is skipped and `LastCheckIn`/`Activity` may be null.

## Usage

From the repository root `auditwindows/`:

```powershell
# Delegated (user) auth — default
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1

# Delegated with device code, custom output, CSV, verbose
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -OutputPath C:\Reports\WindowsAudit -ExportCSV -Verbose

# App-only (certificate) auth with one-time provisioning
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth -CreateAppIfMissing `
  -TenantId '<YOUR_TENANT_GUID>' -AppName 'WindowsAuditApp' -CertSubject 'CN=WindowsAuditApp' `
  -MaxDevices 5 -Verbose

# Subsequent app-only runs (no provisioning)
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth `
  -TenantId '<YOUR_TENANT_GUID>' -AppName 'WindowsAuditApp' -CertSubject 'CN=WindowsAuditApp' -ExportCSV -Verbose

# Use existing connected session and skip module import (avoid assembly conflicts)
Connect-MgGraph -UseDeviceCode -Scopes 'Device.Read.All','Directory.Read.All','BitLockerKey.Read.All','DeviceLocalCredential.Read.All','DeviceManagementManagedDevices.Read.All'
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -SkipModuleImport -ExportCSV -Verbose

# Target a single device by name (quick validation)
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -SkipModuleImport -DeviceName 'DESKTOP-KIJL01G' -Verbose
```

Outputs (default directory is `%USERPROFILE%\Documents`):

- WindowsAudit-YYYY-MM-DD-HH-MM.log
- WindowsAudit-YYYY-MM-DD-HH-MM.xml
- WindowsAudit-YYYY-MM-DD-HH-MM.csv (when `-ExportCSV` is used)

## What’s collected

- Device: Name, DeviceID (directory objectId), AzureAdDeviceId (used for BitLocker/LAPS), Enabled, UserPrincipalName (from Intune), MDM (Intune when present)
- Activity and LastCheckIn (from Intune ManagedDevice)
- BitLocker per drive type (OperatingSystem/Data):
  - BackedUp: ISO 8601 timestamp or boolean true/false (presence)
  - Encrypted: boolean true/false (true when a recovery key is backed up in Entra)
- LAPS availability (existence-only, no secrets retrieved)
  - Available: boolean true/false if the password exists in Entra
  - Retrieved: boolean true/false if the password has been exposed for use 


Lookup details:
- BitLocker keys are queried by Azure AD `deviceId` using Graph (`/informationProtection/bitlocker/recoveryKeys?$filter=deviceId eq '{deviceId}'`).
- LAPS availability is queried with GET-by-ID (`/directory/deviceLocalCredentials/{deviceId}`).

## Logging

Structured log written to the chosen output path.

Example entries:

```
[2025-10-07 13:24:15] INFO: Retrieved 245 Windows devices.
[2025-10-07 13:24:22] WARN: LAPS lookup failed for <DeviceId> (transient), retrying.
[2025-10-07 13:25:10] ERROR: Graph call failed (status=403): Insufficient privileges.
```

Console shows high-level progress (module loads, connection success, query counts), per-device progress bar and "<name> exported" lines. With `-Verbose`, DEBUG entries include Graph operation names, resource paths, elapsed ms, and retry handling (HTTP 429 with Retry-After respected).

## XML schema

Consolidated report root: `<WindowsAudit>` with one `<Device>` per Windows device, including `<BitLocker>` and `<LAPS>` sections. Timestamps are UTC ISO 8601 when available; otherwise boolean `true/false` indicates presence. The `<Device>` node includes `<AzureAdDeviceId>`. Each `<BitLocker>/<Drive>` node includes both `<BackedUp>` and `<Encrypted>`.

Validate the XML using `Demo.xsd`:

```powershell
$xmlPath = "$env:USERPROFILE\Documents\WindowsAudit-YYYY-MM-DD-HH-MM.xml"
$xsdPath = ".\Demo.xsd"

$settings = New-Object System.Xml.XmlReaderSettings
[void]$settings.Schemas.Add('', $xsdPath)
$settings.ValidationType = [System.Xml.ValidationType]::Schema
$settings.ValidationEventHandler += { param($s,$e) ; Write-Host $e.Message -ForegroundColor Red }
$reader = [System.Xml.XmlReader]::Create($xmlPath, $settings)
while ($reader.Read()) { }
$reader.Dispose()
```

## Security notes

- The script never prints BitLocker keys or LAPS passwords to console or logs.
- Only existence/backup status is recorded in XML/CSV.
- When using app-only auth, a self-signed certificate is stored in `Cert:\CurrentUser\My` (unless you supply another). Protect/export it appropriately for automation scenarios.

## Troubleshooting

- Sign-in/consent prompts: ensure your account can consent to delegated scopes listed above.
- 403/insufficient privileges: request the missing Graph permissions or use an appropriate Azure role.
- 429/throttling: the script backs off and retries automatically; re-run later if limits persist.
- No Intune data: if a device isn’t Intune-managed or the scope isn’t granted, `LastCheckIn`/`Activity` will be empty.
- Module import hangs: run with `-SkipModuleImport` to rely on REST fallback, or open a fresh pwsh session, remove old `Microsoft.Graph*` modules, and reinstall the latest.
- BitLocker/LAPS not found: 404 (NotFound) responses are treated as non-fatal and reported as missing (false). If keys exist but volume classification is ambiguous, the OS drive is marked as backed up to avoid false negatives.

## CSV columns

When `-ExportCSV` is used, the CSV also includes:

- `BitLockerOSEncrypted`
- `BitLockerDataEncrypted`

## Roadmap

- Defender for Endpoint status integration
- Compliance policy status (Intune)
- Richer ManagedDevice fields
- Optional HTML report
- Package as a PowerShell module; optional Key Vault storage for certificate/private key; support managed identity where feasible

