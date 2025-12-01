# Setup-AuditWindowsApp.ps1 Execution Flow

This document describes the step-by-step execution flow of the `Setup-AuditWindowsApp.ps1` script, which provisions a dedicated Azure AD application registration for the Audit Windows tool.

---

## Overview

The script creates a dedicated "Audit Windows" app registration in Entra ID with pre-consented Microsoft Graph permissions and optional certificate-based authentication for unattended execution. Supports multiple certificate storage options including local certificate store and Azure Key Vault.

**Total Phases**: 10
**Estimated Duration**: 1-5 minutes (interactive prompts and Key Vault operations may extend this)

---

## Execution Flow

### Phase 1: Environment Validation

**Lines**: 104-164

| Step | Action | Function/Code |
|------|--------|---------------|
| 1.1 | Verify PowerShell 7+ | `#Requires -Version 7.0` directive + runtime check |
| 1.2 | Set strict mode and error handling | `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` |
| 1.3 | Initialize timestamps and output paths | Sets `$script:logPath`, `$script:jsonPath` with timestamp `yyyy-MM-dd-HH-mm` |
| 1.4 | Initialize logging | `Write-SetupLog` function for audit trail |
| 1.5 | Load shared helper module | `Import-Module modules/AuditWindows.Automation.psm1` |
| 1.6 | Load functions from `.\functions` folder | Dot-sources all `.ps1` files in the functions directory |
| 1.7 | Ensure Graph SDK modules available | Installs `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications` if missing |

**Outputs**: Environment ready with all required modules, functions loaded, and logging initialized.

---

### Phase 2: Connect to Microsoft Graph

**Lines**: 166-173
**Function**: `Connect-AuditWindowsGraph`

| Step | Action | Details |
|------|--------|---------|
| 2.1 | Display banner | "=== Audit Windows App Registration Setup ===" |
| 2.2 | Check for existing Graph session | Calls `Get-MgContext` to check for valid session |
| 2.3 | Validate existing session scopes | Checks if session has `Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All` |
| 2.4 | Reuse or authenticate | If valid session exists with required scopes, reuses it; otherwise initiates interactive auth |
| 2.5 | Store tenant ID | Extracts `TenantId` from authenticated context |
| 2.6 | Log connection | Writes to setup log file |

**Required Scopes**:
- `Application.ReadWrite.All`
- `AppRoleAssignment.ReadWrite.All`

**Outputs**: Authenticated `$context` object with `$tenantId`.

---

### Phase 3: Display Configuration and Certificate Options

**Lines**: 175-560

| Step | Action | Details |
|------|--------|---------|
| 3.1 | Display target tenant | Shows the tenant ID |
| 3.2 | Display application name | Shows `$AppDisplayName` (default: "Audit Windows") |
| 3.3 | List permissions to be granted | Calls `Get-AuditWindowsPermissionNames` and displays each |
| 3.4 | Prompt for certificate skip (interactive) | If `-Force` not specified, asks user if they want to skip certificate registration |
| 3.5 | Prompt for certificate store location | Choose between `LocalMachine` (for automation) or `CurrentUser` (interactive only) |
| 3.6 | Check admin privileges | LocalMachine store requires Administrator; offers CurrentUser fallback if not admin |
| 3.7 | Prompt for Key Vault storage (optional) | If not `-Force`, offers Azure Key Vault as certificate storage option |
| 3.8 | Key Vault configuration (if selected) | Prompts for Azure subscription, resource group, vault name |
| 3.9 | Prompt for non-exportable certificate | If using local store, offers non-exportable option for enhanced security |

**Permissions displayed**:
- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

**Certificate Store Options**:
- `LocalMachine` (Cert:\LocalMachine\My) - Recommended for scheduled tasks, requires admin
- `CurrentUser` (Cert:\CurrentUser\My) - For interactive use only

---

### Phase 4: User Confirmation

**Lines**: 562
**Function**: `Confirm-AuditWindowsAction`

| Step | Action | Details |
|------|--------|---------|
| 4.1 | Prompt for confirmation | "Proceed with creating/updating the Audit Windows application registration? (Y/n)" |
| 4.2 | Process response | Enter or 'Y' proceeds; 'N' throws exception and aborts |

**Bypass**: Pass `-Force` parameter to skip confirmation.

---

### Phase 5: Create/Update Application Registration

**Lines**: 564-567
**Function**: `Set-AuditWindowsApplication`

| Step | Action | Graph API |
|------|--------|-----------|
| 5.1 | Search for existing application | `Get-MgApplication -Filter "displayName eq '$DisplayName'"` |
| 5.2a | **If not found**: Create new application | `New-MgApplication` with parameters below |
| 5.2b | **If found**: Update existing application | `Update-MgApplication` if settings need updating |
| 5.3 | Retrieve final application object | `Get-MgApplication -ApplicationId $app.Id` |
| 5.4 | Log operation | Writes AppId and ObjectId to setup log |

**Application Configuration**:
```
DisplayName:            $AppDisplayName (default: "Audit Windows")
SignInAudience:         AzureADMyOrg (single tenant)
IsFallbackPublicClient: true
PublicClient.RedirectUris:
  - http://localhost
  - https://login.microsoftonline.com/common/oauth2/nativeclient
Web.HomePageUrl:        https://github.com/kkaminsk/auditwindows
```

**Outputs**: `$app` - Application object with `AppId` and `Id`.

---

### Phase 6: Upload Application Logo (Optional)

**Lines**: 569-572
**Function**: `Set-AuditWindowsLogo`

| Step | Action | Details |
|------|--------|---------|
| 6.1 | Check for `logo.jpg` | Looks for `logo.jpg` in the script directory (`$PSScriptRoot`) |
| 6.2a | **If found**: Upload logo | `Set-MgApplicationLogo -ApplicationId $app.Id -InFile $logoPath` |
| 6.2b | **If not found**: Display warning | Warns that app will use default icon |
| 6.3 | Log result | Writes logo upload status to setup log |

**Requirements**: JPEG file, under 100 KB.

**Outputs**: `$logoUploaded` - Boolean indicating success.

---

### Phase 7: Create Service Principal

**Lines**: 574-577
**Function**: `Get-AuditWindowsServicePrincipal`

| Step | Action | Graph API |
|------|--------|-----------|
| 7.1 | Search for existing service principal | `Get-MgServicePrincipal -Filter "appId eq '$AppId'"` |
| 7.2a | **If not found**: Create service principal | `New-MgServicePrincipal -AppId $AppId` |
| 7.2b | **If found**: Reuse existing | Returns existing service principal |
| 7.3 | Log result | Writes service principal ObjectId to setup log |

**Outputs**: `$sp` - Service principal object with `Id`.

---

### Phase 8: Configure Permissions and Grant Admin Consent

**Lines**: 579-582
**Function**: `Set-AuditWindowsPermissions` → `Grant-AuditWindowsConsent`

#### 8a. Configure Required Resource Access

| Step | Action | Details |
|------|--------|---------|
| 8a.1 | Get Microsoft Graph service principal | `Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"` |
| 8a.2 | Build resource access payload | `Get-AuditWindowsGraphResourceAccess` maps permission names to Graph role IDs |
| 8a.3 | Update application permissions | `Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $resourceAccess` |

#### 8b. Grant Admin Consent

**Function**: `Grant-AuditWindowsConsent`

| Step | Action | Graph API |
|------|--------|-----------|
| 8b.1 | Get existing role assignments | `Get-MgServicePrincipalAppRoleAssignment` |
| 8b.2 | For each permission not already consented | `New-MgServicePrincipalAppRoleAssignment` |
| 8b.3 | Display consent status | Lists each permission as granted or already consented |

**Permissions Granted** (Application type):

| Permission | Role ID |
|------------|---------|
| `Device.Read.All` | (looked up from Graph SP) |
| `BitLockerKey.ReadBasic.All` | (looked up from Graph SP) |
| `DeviceLocalCredential.ReadBasic.All` | (looked up from Graph SP) |
| `DeviceManagementManagedDevices.Read.All` | (looked up from Graph SP) |

---

### Phase 9: Add Certificate Credential (Optional)

**Lines**: 584-714
**Functions**: `Set-AuditWindowsKeyCredential` (local), `Get-AuditWindowsKeyVaultCertificate` (Key Vault)

**Skipped if**: `-SkipCertificate` is specified or user chose to skip in Phase 3.

#### 9a. Key Vault Certificate Path (if `-UseKeyVault`)

| Step | Action | Details |
|------|--------|---------|
| 9a.1 | Validate `-VaultName` provided | Throws if missing |
| 9a.2 | Ensure Azure subscription selected | `Select-AuditWindowsSubscription` if not already set |
| 9a.3 | Create resource group if needed | `New-AzResourceGroup` if `-CreateResourceGroupIfMissing` |
| 9a.4 | Create Key Vault if needed | `New-AzKeyVault` with RBAC authorization |
| 9a.5 | Create/retrieve certificate | `Add-AzKeyVaultCertificate` or `Get-AzKeyVaultCertificate` |
| 9a.6 | Download to local store | Certificate synced to `Cert:\$CertificateStoreLocation\My` |
| 9a.7 | Handle RBAC errors | Provides detailed guidance for access denied scenarios |
| 9a.8 | Attach certificate to application | `Update-MgApplication -KeyCredentials` |

#### 9b. Local Certificate Path (if not `-UseKeyVault`)

| Step | Action | Details |
|------|--------|---------|
| 9b.1 | Check for existing thumbprint | If `-ExistingCertificateThumbprint` provided, locate in `Cert:\CurrentUser\My` |
| 9b.2 | **If not provided**: Generate new certificate | `New-SelfSignedCertificate` with parameters below |

**Certificate Parameters** (new certificate):
```
Subject:           $CertificateSubject (default: CN=AuditWindowsCert)
CertStoreLocation: Cert:\$CertificateStoreLocation\My (LocalMachine or CurrentUser)
KeyExportPolicy:   Exportable or NonExportable (based on -NonExportable switch)
KeySpec:           Signature
KeyLength:         2048
KeyAlgorithm:      RSA
HashAlgorithm:     SHA256
NotAfter:          (Current date + $CertificateValidityInMonths months)
```

#### 9c. Certificate Export (Optional, Local Only)

| Step | Action | Details |
|------|--------|---------|
| 9c.1 | **If `-NonExportable`**: Skip export | Non-exportable certificates cannot be backed up |
| 9c.2 | Prompt for export skip | "Skip certificate file backup? (y/N)" |
| 9c.3a | **If not skipped**: Export .cer | `Export-Certificate -Type CERT` to `$USERPROFILE\AuditWindowsCert.cer` |
| 9c.3b | **If not skipped**: Export .pfx | `Export-PfxCertificate` with user-provided password to `$USERPROFILE\AuditWindowsCert.pfx` |

**Skipped if**: `-SkipCertificateExport` is specified or `-NonExportable` is used.

#### 9d. Attach Certificate to Application

| Step | Action | Graph API |
|------|--------|-----------|
| 9d.1 | Check if certificate already attached | `Find-AuditWindowsKeyCredential` searches existing `KeyCredentials` |
| 9d.2 | **If not attached**: Add key credential | `Update-MgApplication -KeyCredentials @($keyCredential)` |
| 9d.3 | **If replacing**: Warn user | Notes that existing certificates will be replaced |

**KeyCredential Structure**:
```
Type:          AsymmetricX509Cert
Usage:         Verify
Key:           (certificate RawData)
DisplayName:   AuditWindows-{Thumbprint} or AuditWindows-KeyVault-{Thumbprint}
StartDateTime: Certificate NotBefore
EndDateTime:   Certificate NotAfter
```

**Outputs**: `$certificate` - Certificate object with `Thumbprint` and `NotAfter`.

---

### Phase 10: Output Summary and Cleanup

**Lines**: 716-818
**Functions**: `Disconnect-AuditWindowsGraph`

#### 10a. Create Comprehensive JSON Summary

| Section | Fields |
|---------|--------|
| `Metadata` | `GeneratedAt`, `GeneratedBy`, `ComputerName`, `ScriptVersion`, `LogFile` |
| `ApplicationRegistration` | `DisplayName`, `ApplicationId`, `ObjectId`, `TenantId`, `SignInAudience`, `CreatedDateTime` |
| `ServicePrincipal` | `ObjectId`, `AppId`, `DisplayName` |
| `Certificate` | `Configured`, `Thumbprint`, `Subject`, `NotBefore`, `NotAfter`, `StoreLocation`, `StorePath`, `KeyVaultEnabled`, `KeyVaultName`, `KeyVaultCertName` |
| `Permissions` | `Type`, `GrantedPermissions`, `ConsentGranted` |
| `Configuration` | `LogoUploaded` |

#### 10b. Export Outputs

| Step | Action | Details |
|------|--------|---------|
| 10b.1 | Export JSON summary | Writes to `Setup-AuditWindowsApp-{timestamp}.json` (unless `-SkipSummaryExport`) |
| 10b.2 | Log completion | Writes duration to setup log file |

**Skipped if**: `-SkipSummaryExport` is specified.

#### 10c. Display Console Summary

| Step | Action | Details |
|------|--------|---------|
| 10c.1 | Display Application ID | Green color |
| 10c.2 | Display Tenant ID | Green color |
| 10c.3 | Display Certificate info | Thumbprint, expiry date, store location |
| 10c.4 | Display Key Vault name | If `-UseKeyVault` was used |
| 10c.5 | Display Logo status | Green color |
| 10c.6 | Display output file paths | JSON and log file locations |

#### 10d. Display Next Steps

| Message | Condition |
|---------|-----------|
| "Run Get-EntraWindowsDevices.ps1 to use this dedicated app with interactive auth" | Always |
| "Or use -UseAppAuth -TenantId '...' for certificate-based app-only auth" | If certificate was created |
| "Optionally configure Conditional Access policies targeting 'Audit Windows'" | Always |
| "(Re-run with certificate to enable app-only auth for automation)" | If certificate was skipped |

#### 10e. Open Entra Portal

| Step | Action | Details |
|------|--------|---------|
| 10e.1 | Launch browser | Opens app overview in Entra Portal |
| 10e.2 | Fallback | Displays URL if browser launch fails |

#### 10f. Disconnect from Graph

**Function**: `Disconnect-AuditWindowsGraph`

| Step | Action | Details |
|------|--------|---------|
| 10f.1 | Disconnect Graph session | `Disconnect-MgGraph` |

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Setup-AuditWindowsApp.ps1                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Environment Validation                                  │
│   • Check PowerShell 7+                                         │
│   • Load AuditWindows.Automation module                         │
│   • Load functions from .\functions                             │
│   • Install/Import Microsoft.Graph modules                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 2: Connect-AuditWindowsGraph                               │
│   • Check existing session and scopes                            │
│   • Interactive auth if needed (browser)                         │
│   • Required: Application.ReadWrite.All, AppRoleAssignment.*    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3-4: Display Config & Confirm                              │
│   • Show tenant, app name, permissions                           │
│   • Ask: Skip certificate? (unless -Force)                       │
│   • Confirm: Proceed? (Y/n)                                      │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 5: Set-AuditWindowsApplication                             │
│   ┌──────────────┐     ┌──────────────┐                         │
│   │ App exists?  │─No─▶│ Create new   │                         │
│   └──────────────┘     │ application  │                         │
│          │Yes          └──────────────┘                         │
│          ▼                    │                                  │
│   ┌──────────────┐            │                                  │
│   │ Update if    │◀───────────┘                                  │
│   │ needed       │                                               │
│   └──────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 6: Set-AuditWindowsLogo                                    │
│   • Check for logo.jpg in script directory                       │
│   • Upload if found, warn if missing                             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 7: Get-AuditWindowsServicePrincipal                        │
│   • Find or create service principal for the app                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 8: Set-AuditWindowsPermissions                             │
│   • Build RequiredResourceAccess for Microsoft Graph             │
│   • Update application with permissions                          │
│   • Grant-AuditWindowsConsent:                                   │
│     - Create AppRoleAssignments for each permission              │
│     - Admin consent granted automatically                        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 9: Set-AuditWindowsKeyCredential (if not -SkipCertificate)│
│   ┌─────────────────┐     ┌─────────────────┐                   │
│   │ Existing cert   │─No─▶│ Generate new    │                   │
│   │ thumbprint?     │     │ self-signed     │                   │
│   └─────────────────┘     └─────────────────┘                   │
│          │Yes                    │                               │
│          ▼                       ▼                               │
│   ┌─────────────────┐     ┌─────────────────┐                   │
│   │ Locate in       │     │ Export .cer/.pfx│                   │
│   │ Cert:\CurrentUser│     │ (optional)      │                   │
│   └─────────────────┘     └─────────────────┘                   │
│          │                       │                               │
│          └───────────┬───────────┘                               │
│                      ▼                                           │
│            ┌─────────────────┐                                   │
│            │ Attach cert to  │                                   │
│            │ app KeyCredentials│                                 │
│            └─────────────────┘                                   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 10: Summary & Cleanup                                      │
│   • Create summary record                                        │
│   • Display to console                                           │
│   • Export AuditWindowsAppSummary.json                          │
│   • Open Entra Portal (browser)                                  │
│   • Show next steps                                              │
│   • Disconnect-AuditWindowsGraph                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `AppDisplayName` | string | `'Audit Windows'` | Display name for the app registration |
| `CertificateSubject` | string | `'CN=AuditWindowsCert'` | Subject for the self-signed certificate |
| `CertificateValidityInMonths` | int | `24` | Certificate validity period (1-60 months) |
| `ExistingCertificateThumbprint` | string | - | Use an existing certificate instead of generating new |
| `SkipCertificate` | switch | - | Skip certificate registration entirely |
| `SkipCertificateExport` | switch | - | Skip exporting certificate to .cer/.pfx files |
| `NonExportable` | switch | - | Create certificate with non-exportable private key (more secure, no backup) |
| `UseKeyVault` | switch | - | Use Azure Key Vault for certificate storage instead of local store |
| `VaultName` | string | - | Name of the Azure Key Vault (required with `-UseKeyVault`) |
| `KeyVaultCertificateName` | string | `'AuditWindowsCert'` | Name of the certificate in Key Vault |
| `CreateVaultIfMissing` | switch | - | Create the Key Vault if it doesn't exist |
| `KeyVaultResourceGroupName` | string | - | Resource group for new Key Vault (required with `-CreateVaultIfMissing`) |
| `KeyVaultLocation` | string | - | Azure region for new Key Vault (required with `-CreateVaultIfMissing`) |
| `KeyVaultSubscriptionId` | string | - | Azure subscription ID for Key Vault operations |
| `CertificateStoreLocation` | string | `'LocalMachine'` | Certificate store: `LocalMachine` or `CurrentUser` |
| `TenantId` | string | - | Target tenant ID (uses authenticated context if not specified) |
| `Force` | switch | - | Skip all confirmation prompts |
| `Reauth` | switch | - | Force re-authentication |
| `SkipSummaryExport` | switch | - | Skip exporting summary JSON file |
| `SummaryOutputPath` | string | - | Custom path for summary JSON file |

---

## Files Created/Modified

| File | Location | Description |
|------|----------|-------------|
| `Setup-AuditWindowsApp-{timestamp}.json` | Script directory or `-SummaryOutputPath` | Comprehensive JSON summary of provisioning |
| `Setup-AuditWindowsApp-{timestamp}.log` | Script directory | Timestamped execution log |
| `AuditWindowsCert.cer` | `$USERPROFILE` | Public certificate (optional, exportable certs only) |
| `AuditWindowsCert.pfx` | `$USERPROFILE` | Private certificate with password (optional, exportable certs only) |
| Certificate | `Cert:\LocalMachine\My` or `Cert:\CurrentUser\My` | Self-signed certificate in Windows store |
| Key Vault Certificate | Azure Key Vault | HSM-backed certificate (if `-UseKeyVault` used) |

---

## Error Handling

| Phase | Error Condition | Behavior |
|-------|-----------------|----------|
| 1 | PowerShell version < 7 | Throws exception, script exits |
| 1 | Missing modules/functions folder | Throws exception, script exits |
| 2 | Auth failed or cancelled | Throws exception, script exits |
| 3 | Not running as admin (LocalMachine store) | Offers CurrentUser fallback or exits |
| 4 | User types 'N' at confirmation | Throws "Operation cancelled by user." |
| 5 | Application creation fails | Throws exception with Graph error |
| 6 | Logo upload fails | Warns and continues (non-fatal) |
| 8 | Permission grant fails | Throws exception (requires admin role) |
| 9 | Certificate generation/attach fails | Throws exception |
| 9 | Key Vault access denied | Displays RBAC guidance, offers to assign roles |
| 9 | Key Vault RBAC timeout | Provides retry instructions |
| 9 | Key Vault creation fails | Throws exception with Azure error |

---

## Required Azure AD Roles

One of the following roles is required for the authenticating user:

- **Global Administrator** — Full access
- **Application Administrator** — Can create apps and grant consent
- **Cloud Application Administrator** — Can create apps and grant consent (for non-privileged permissions)

---

## Required Azure RBAC Roles (Key Vault)

When using `-UseKeyVault`, the following Azure RBAC roles are required:

| Role | Scope | Purpose |
|------|-------|---------|
| **Key Vault Certificates Officer** | Key Vault | Create and manage certificates |
| **Key Vault Secrets User** | Key Vault | Download certificate with private key |
| **Contributor** or **Key Vault Contributor** | Resource Group | Create new Key Vault (if `-CreateVaultIfMissing`) |

---

## Certificate Storage Options

| Option | Security Level | Use Case | Trade-offs |
|--------|----------------|----------|------------|
| Azure Key Vault (`-UseKeyVault`) | Highest | Production, multi-machine | Requires Azure subscription, network access |
| Non-Exportable (`-NonExportable`) | High | Single machine, no backup needed | Cannot migrate or backup certificate |
| Exportable (default) | Standard | Development, needs backup | Private key can be extracted |

---

## Certificate Store Locations

| Store | Path | Requirements | Use Case |
|-------|------|--------------|----------|
| LocalMachine | `Cert:\LocalMachine\My` | Administrator privileges | Scheduled tasks, services |
| CurrentUser | `Cert:\CurrentUser\My` | No special privileges | Interactive use only |
