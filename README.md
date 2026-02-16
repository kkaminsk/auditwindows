# auditwindows
Windows Audit Application (PowerShell 7) to inventory Windows devices from Entra ID via Microsoft Graph and report BitLocker and LAPS posture.

## Version

1.2 (2025-12-01)

- Permissions reduced
- Non-Interactive mode optional
  - Disabled by default
  - Certificate backup optional
- **Enhanced certificate storage options**
  - Non-exportable certificates (`-NonExportable`) for stronger security
  - Azure Key Vault integration (`-UseKeyVault`) for centralized, HSM-backed storage
  - Automatic Key Vault and resource group provisioning
  - Certificate health monitoring with expiration warnings
  - Support for `LocalMachine` certificate store (for scheduled tasks)
- Two scripts for use
  - Setup script for custom application registration
    - Better access control
    - Conditional access controls
    - Better logging
    - Branding
      - Logo
      - URL
  - Execution script for collecting data
    - Looks for the Audit Windows Application in Entra
    - Logs output CSV and XML in the documents folder.

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

### Setup-AuditWindowsApp.ps1

**Required Azure AD Role**:

| Role | Purpose |
|------|---------|
| **Global Administrator** | Full access to create apps, grant consent, manage all settings |
| **Application Administrator** | Create/manage app registrations and grant admin consent (Recommended) |
| **Cloud Application Administrator** | Same as above, but cannot manage on-premises apps |

**Required Microsoft Graph Scopes** (requested interactively):

- `Application.ReadWrite.All` — Create and update app registrations
- `AppRoleAssignment.ReadWrite.All` — Grant admin consent for app permissions

---

### Get-EntraWindowsDevices.ps1

**Required Azure AD Role**:

| Role | Covers |
|------|--------|
| **Global Reader** | Device.Read.All, BitLockerKey.ReadBasic.All, DeviceLocalCredential.ReadBasic.All |
| **Intune Administrator** | All above + DeviceManagementManagedDevices.Read.All (Recommended) |
| **Security Reader** | Device.Read.All, BitLockerKey.ReadBasic.All |
| **Cloud Device Administrator** | Device.Read.All only |

**Delegated Microsoft Graph Scopes** (interactive mode):

- `Device.Read.All` — Read device information from Entra ID
- `BitLockerKey.ReadBasic.All` — Read BitLocker recovery key metadata
- `DeviceLocalCredential.ReadBasic.All` — Check LAPS credential availability
- `DeviceManagementManagedDevices.Read.All` — Read Intune managed device info (LastCheckIn/Activity)

**Application Permissions** (app-only mode with `-UseAppAuth`):

- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

**Provisioning Scopes** (when using `-CreateAppIfMissing`):

- `Application.ReadWrite.All`
- `AppRoleAssignment.ReadWrite.All`

> **Note:** If `DeviceManagementManagedDevices.Read.All` isn't granted, Intune enrichment is skipped and `LastCheckIn`/`Activity` will be null.

## Setup: Dedicated App Registration (Recommended)

For production use, create a dedicated "Audit Windows" app registration instead of using the shared Microsoft Graph PowerShell app. This provides:

- **Clear audit trail** — Sign-ins logged under "Audit Windows" in Entra
- **Conditional Access** — Target policies specifically to this tool
- **Pre-consented permissions** — No user self-consent required
- **Independent lifecycle** — Revoke without affecting other Graph PowerShell usage

### Setup-AuditWindowsApp.ps1

The `Setup-AuditWindowsApp.ps1` script automates the provisioning of a dedicated Azure AD app registration for the Audit Windows tool.

#### What it does

1. **Creates or updates** the "Audit Windows" app registration (single-tenant)
2. **Configures public client** authentication for interactive desktop use
3. **Sets homepage URL** to https://github.com/kkaminsk/auditwindows
4. **Uploads a logo** if `logo.jpg` is present in the script directory
5. **Adds Microsoft Graph permissions** (both application and delegated) and grants admin consent:
   - Device.Read.All
   - BitLockerKey.ReadBasic.All
   - DeviceLocalCredential.ReadBasic.All
   - DeviceManagementManagedDevices.Read.All
6. **Optionally generates a certificate credential** (X.509, no client secrets) for app-only authentication
7. **Outputs a JSON summary** with app details for operational records
8. **Opens the Entra Portal** to the app's overview page for verification
9. **Disconnects from Microsoft Graph** when complete

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-AppDisplayName` | string | `'Audit Windows'` | Display name for the app registration |
| `-CertificateSubject` | string | `'CN=AuditWindowsCert'` | Subject name for the generated certificate |
| `-CertificateValidityInMonths` | int | `24` | Certificate validity (1-60 months) |
| `-ExistingCertificateThumbprint` | string | — | Use an existing certificate from `Cert:\CurrentUser\My` |
| `-SkipCertificate` | switch | — | Skip certificate registration (interactive auth only) |
| `-SkipCertificateExport` | switch | — | Skip exporting certificate to `.cer`/`.pfx` files |
| `-NonExportable` | switch | — | Create certificate with non-exportable private key |
| `-CertificateStoreLocation` | string | `'CurrentUser'` | Certificate store location: `CurrentUser` or `LocalMachine` |
| `-UseKeyVault` | switch | — | Use Azure Key Vault for certificate storage |
| `-VaultName` | string | — | Name of the Azure Key Vault (required with `-UseKeyVault`) |
| `-KeyVaultCertificateName` | string | `'AuditWindowsCert'` | Name of the certificate in Key Vault |
| `-CreateVaultIfMissing` | switch | — | Create the Key Vault if it doesn't exist |
| `-KeyVaultResourceGroupName` | string | — | Resource group for new Key Vault (with `-CreateVaultIfMissing`) |
| `-KeyVaultLocation` | string | — | Azure region for new Key Vault (with `-CreateVaultIfMissing`) |
| `-KeyVaultSubscriptionId` | string | — | Azure subscription for Key Vault operations |
| `-TenantId` | string | — | Target tenant ID (defaults to authenticated context) |
| `-Force` | switch | — | Skip confirmation prompts |
| `-Reauth` | switch | — | Force re-authentication even if session exists |
| `-SkipSummaryExport` | switch | — | Skip exporting the summary JSON file |
| `-SummaryOutputPath` | string | — | Custom path for the summary JSON file |

#### Requirements

- PowerShell 7+
- Run as **Global Administrator** or **Application Administrator**
- Microsoft Graph PowerShell SDK (auto-installed if missing)

#### Usage Examples

```powershell
# Basic setup with default settings (interactive)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1

# Specify tenant and skip confirmation prompts
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -TenantId 'contoso.onmicrosoft.com' -Force

# Use a custom app name
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -AppDisplayName 'Windows Security Audit'

# Use an existing certificate instead of generating a new one
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -ExistingCertificateThumbprint 'ABC123DEF456...'

# Generate certificate with longer validity
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -CertificateValidityInMonths 36

# Force re-authentication (useful if previous session has wrong permissions)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -Reauth

# Interactive auth only (skip certificate for app-only auth)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -SkipCertificate

# Create non-exportable certificate (more secure, cannot be backed up)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -NonExportable

# Use Azure Key Vault for certificate storage (existing vault)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'mykeyvault'

# Auto-provision Key Vault and resource group
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'auditwindows-kv' `
  -CreateVaultIfMissing -KeyVaultResourceGroupName 'auditwindows-rg' -KeyVaultLocation 'eastus'

# Use LocalMachine store for scheduled tasks (requires admin)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -CertificateStoreLocation LocalMachine
```

#### Output Files

| File | Location | Description |
|------|----------|-------------|
| `AuditWindowsAppSummary.json` | `%USERPROFILE%` | JSON with AppId, TenantId, certificate thumbprint, expiration |
| `AuditWindowsCert.cer` | `%USERPROFILE%` | Public certificate (optional, when certificate is created) |
| `AuditWindowsCert.pfx` | `%USERPROFILE%` | Private certificate (optional, password-protected) |

#### Prerequisites

You must run `Setup-AuditWindowsApp.ps1` before using `Get-EntraWindowsDevices.ps1`. The audit script requires a pre-configured "Audit Windows" app registration with admin-consented permissions.

## Usage

From the repository root `auditwindows/`:

```powershell
# First-time setup: Create the app registration (run once per tenant)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1

# Interactive auth using the dedicated "Audit Windows" app
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1

# With device code flow (for headless/remote sessions)
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseDeviceCode

# With custom output path and CSV export
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -OutputPath C:\Reports\WindowsAudit -ExportCSV -Verbose

# App-only (certificate) auth with one-time provisioning
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth -CreateAppIfMissing `
  -TenantId '<YOUR_TENANT_GUID>' -AppName 'WindowsAuditApp' -CertSubject 'CN=WindowsAuditApp' `
  -MaxDevices 5 -Verbose

# Subsequent app-only runs (no provisioning)
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth `
  -TenantId '<YOUR_TENANT_GUID>' -AppName 'WindowsAuditApp' -CertSubject 'CN=WindowsAuditApp' -ExportCSV -Verbose

# Use existing connected session and skip module import (avoid assembly conflicts)
Connect-MgGraph -UseDeviceCode -Scopes 'Device.Read.All','BitLockerKey.ReadBasic.All','DeviceLocalCredential.ReadBasic.All','DeviceManagementManagedDevices.Read.All'
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
  - Data drive key detection in place but no check for fixed drive
- LAPS availability (existence-only, no secrets retrieved)
  - Available: boolean true/false if the password exists in Entra
  - Retrieved: boolean true/false if the password has been exposed for use 


Lookup details:
- BitLocker keys are queried by Azure AD `deviceId` using Graph (`/informationProtection/bitlocker/recoveryKeys?$filter=deviceId eq '{deviceId}'`).
- LAPS availability is queried with GET-by-ID (`/devices/{id}/localCredentials`).

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

## Certificate Storage Options

The Audit Windows tool supports multiple certificate storage options for app-only authentication, each with different security characteristics.

### Storage Option Comparison

| Feature | Exportable (Default) | Non-Exportable | Azure Key Vault |
|---------|---------------------|----------------|-----------------|
| Private key backup | Yes (.pfx export) | No | Automatic |
| Migration to another machine | Yes | No | Yes (download from vault) |
| Protection against theft | Low | Medium | High (HSM with Premium) |
| Additional infrastructure | None | None | Azure Key Vault |
| Audit logging | Windows Security Log | Windows Security Log | Azure Monitor |
| Recovery if lost | Restore from .pfx | Re-run setup script | Download from vault |
| Auto-provisioning | N/A | N/A | Yes (`-CreateVaultIfMissing`) |
| Store location options | CurrentUser, LocalMachine | CurrentUser, LocalMachine | CurrentUser, LocalMachine |

### Option 1: Exportable Certificate (Default)

Standard certificate with exportable private key. Can be backed up to `.pfx` file.

```powershell
# Default behavior - certificate can be exported
.\Setup-AuditWindowsApp.ps1

# Explicitly skip export prompt
.\Setup-AuditWindowsApp.ps1 -SkipCertificateExport
```

**Trade-offs:**
- Any process running under the same user can export the private key
- Risk of credential theft on compromised workstations
- Can be backed up and migrated (useful for disaster recovery)

### Option 2: Non-Exportable Certificate (Recommended for Security)

Certificate with non-exportable private key. Cannot be backed up but provides stronger protection.

```powershell
# Create non-exportable certificate
.\Setup-AuditWindowsApp.ps1 -NonExportable

# Or respond "Y" when prompted in interactive mode
```

**Trade-offs:**
- Private key cannot be exported (protection against theft)
- Cannot backup or migrate to another machine
- If certificate is lost, run `Setup-AuditWindowsApp.ps1` again to regenerate

### Option 3: Azure Key Vault (Production Recommendation)

Store certificate in Azure Key Vault for centralized, HSM-backed storage with audit logging.

```powershell
# Setup with existing Key Vault
.\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'mykeyvault'

# Auto-provision Key Vault and resource group
.\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'auditwindows-kv' `
  -CreateVaultIfMissing -KeyVaultResourceGroupName 'auditwindows-rg' -KeyVaultLocation 'eastus'

# Run audit with Key Vault certificate
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId '<tenant-id>' -UseKeyVault -VaultName 'mykeyvault'
```

**Prerequisites:**
1. Azure Key Vault with appropriate permissions (or use `-CreateVaultIfMissing` to auto-provision)
2. `Az.KeyVault` PowerShell module: `Install-Module -Name Az.KeyVault -Scope CurrentUser`
3. Azure authentication: `Connect-AzAccount`
4. Required Azure roles for Key Vault access:
   - `Key Vault Certificates Officer` — Create and manage certificates
   - `Key Vault Secrets User` — Download certificate with private key

**For HSM-backed keys** (recommended for production):
```bash
az keyvault create --name 'mykeyvault' --resource-group 'mygroup' --sku premium --location 'eastus'
```

**Trade-offs:**
- Highest security with HSM backing (Premium SKU)
- Centralized management and audit logging
- Certificate rotation without re-deploying scripts
- Auto-waits for RBAC propagation when creating new vaults
- Requires Azure infrastructure and authentication

### Certificate Store Locations

By default, certificates are stored in `Cert:\CurrentUser\My`. For scheduled tasks or service accounts, use `-CertificateStoreLocation LocalMachine`:

```powershell
# Store in LocalMachine (requires admin privileges)
.\Setup-AuditWindowsApp.ps1 -CertificateStoreLocation LocalMachine

# Key Vault with LocalMachine store
.\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'mykeyvault' -CertificateStoreLocation LocalMachine
```

| Store Location | Use Case | Requirements |
|----------------|----------|--------------|
| `CurrentUser` | Interactive use, development | None |
| `LocalMachine` | Scheduled tasks, service accounts | Run as Administrator |

### Certificate Expiration Monitoring

The tool includes certificate health checks that warn when certificates are expiring. Use `Test-AuditWindowsCertificateHealth` to check certificate status:

```powershell
# Check default certificate (CN=AuditWindowsCert)
$health = Test-AuditWindowsCertificateHealth
if (-not $health.Healthy) {
    Write-Warning $health.Message
}

# Custom warning threshold (60 days instead of default 30)
$health = Test-AuditWindowsCertificateHealth -WarningDaysBeforeExpiry 60

# Check specific certificate by thumbprint
$health = Test-AuditWindowsCertificateHealth -CertificateThumbprint 'ABC123...'

# Check certificate with custom subject
$health = Test-AuditWindowsCertificateHealth -CertificateSubject 'CN=MyCustomCert'
```

**Health Check Return Values:**

| Property | Description |
|----------|-------------|
| `Healthy` | `$true` if valid and not expiring within threshold |
| `DaysUntilExpiry` | Days until expiration (negative if expired) |
| `Certificate` | The certificate object (or `$null` if not found) |
| `Message` | Human-readable status message |

**Recommendations:**
- Set up scheduled monitoring for certificate expiration (30-day warning threshold)
- For Key Vault, configure certificate auto-renewal policies
- Document certificate renewal procedures in your runbook

## Security notes

- The script never prints BitLocker keys or LAPS passwords to console or logs.
- Only existence/backup status is recorded in XML/CSV.
- When using app-only auth, a self-signed certificate is stored in `Cert:\CurrentUser\My` (unless you supply another). Protect/export it appropriately for automation scenarios.
- **Recommended:** Use `-NonExportable` for single-machine deployments or `-UseKeyVault` for multi-machine or production environments.

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
- Package as a PowerShell module
- Support managed identity for Azure-hosted scenarios

