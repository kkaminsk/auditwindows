# Setup-AuditWindowsApp.ps1 Execution Flow

This document describes the step-by-step execution flow of the `Setup-AuditWindowsApp.ps1` script, which provisions a dedicated Azure AD application registration for the Audit Windows tool.

---

## Overview

The script creates a dedicated "Audit Windows" app registration in Entra ID with pre-consented Microsoft Graph permissions and optional certificate-based authentication for unattended execution.

**Total Phases**: 10  
**Estimated Duration**: 1-3 minutes (interactive prompts may extend this)

---

## Execution Flow

### Phase 1: Environment Validation

**Lines**: 67-101

| Step | Action | Function/Code |
|------|--------|---------------|
| 1.1 | Verify PowerShell 7+ | Direct check: `$PSVersionTable.PSVersion.Major -lt 7` |
| 1.2 | Set strict mode and error handling | `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` |
| 1.3 | Load shared helper module | `Import-Module modules/AuditWindows.Automation.psm1` |
| 1.4 | Load functions from `.\functions` folder | Dot-sources all `.ps1` files in the functions directory |
| 1.5 | Ensure Graph SDK modules available | Installs `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications` if missing |

**Outputs**: Environment ready with all required modules and functions loaded.

---

### Phase 2: Connect to Microsoft Graph

**Lines**: 103-108  
**Function**: `Connect-AuditWindowsGraph`

| Step | Action | Details |
|------|--------|---------|
| 2.1 | Display banner | "=== Audit Windows App Registration Setup ===" |
| 2.2 | Check for existing Graph session | Calls `Get-MgContext` to check for valid session |
| 2.3 | Validate existing session scopes | Checks if session has `Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All` |
| 2.4 | Reuse or authenticate | If valid session exists with required scopes, reuses it; otherwise initiates interactive auth |
| 2.5 | Store tenant ID | Extracts `TenantId` from authenticated context |

**Required Scopes**:
- `Application.ReadWrite.All`
- `AppRoleAssignment.ReadWrite.All`

**Outputs**: Authenticated `$context` object with `$tenantId`.

---

### Phase 3: Display Configuration Summary

**Lines**: 110-127

| Step | Action | Details |
|------|--------|---------|
| 3.1 | Display target tenant | Shows the tenant ID |
| 3.2 | Display application name | Shows `$AppDisplayName` (default: "Audit Windows") |
| 3.3 | List permissions to be granted | Calls `Get-AuditWindowsPermissionNames` and displays each |
| 3.4 | Prompt for certificate skip (interactive) | If `-Force` not specified, asks user if they want to skip certificate registration |

**Permissions displayed**:
- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

---

### Phase 4: User Confirmation

**Lines**: 129  
**Function**: `Confirm-AuditWindowsAction`

| Step | Action | Details |
|------|--------|---------|
| 4.1 | Prompt for confirmation | "Proceed with creating/updating the Audit Windows application registration? (Y/n)" |
| 4.2 | Process response | Enter or 'Y' proceeds; 'N' throws exception and aborts |

**Bypass**: Pass `-Force` parameter to skip confirmation.

---

### Phase 5: Create/Update Application Registration

**Lines**: 131-132  
**Function**: `Set-AuditWindowsApplication`

| Step | Action | Graph API |
|------|--------|-----------|
| 5.1 | Search for existing application | `Get-MgApplication -Filter "displayName eq '$DisplayName'"` |
| 5.2a | **If not found**: Create new application | `New-MgApplication` with parameters below |
| 5.2b | **If found**: Update existing application | `Update-MgApplication` if settings need updating |
| 5.3 | Retrieve final application object | `Get-MgApplication -ApplicationId $app.Id` |

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

**Lines**: 134-135  
**Function**: `Set-AuditWindowsLogo`

| Step | Action | Details |
|------|--------|---------|
| 6.1 | Check for `logo.jpg` | Looks for `logo.jpg` in the script directory (`$PSScriptRoot`) |
| 6.2a | **If found**: Upload logo | `Set-MgApplicationLogo -ApplicationId $app.Id -InFile $logoPath` |
| 6.2b | **If not found**: Display warning | Warns that app will use default icon |

**Requirements**: JPEG file, under 100 KB.

**Outputs**: `$logoUploaded` - Boolean indicating success.

---

### Phase 7: Create Service Principal

**Lines**: 137-138  
**Function**: `Get-AuditWindowsServicePrincipal`

| Step | Action | Graph API |
|------|--------|-----------|
| 7.1 | Search for existing service principal | `Get-MgServicePrincipal -Filter "appId eq '$AppId'"` |
| 7.2a | **If not found**: Create service principal | `New-MgServicePrincipal -AppId $AppId` |
| 7.2b | **If found**: Reuse existing | Returns existing service principal |

**Outputs**: `$sp` - Service principal object with `Id`.

---

### Phase 8: Configure Permissions and Grant Admin Consent

**Lines**: 140-141  
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

**Lines**: 143-154  
**Function**: `Set-AuditWindowsKeyCredential`

**Skipped if**: `-SkipCertificate` is specified or user chose to skip in Phase 3.

#### 9a. Certificate Acquisition

| Step | Action | Details |
|------|--------|---------|
| 9a.1 | Check for existing thumbprint | If `-ExistingCertificateThumbprint` provided, locate in `Cert:\CurrentUser\My` |
| 9a.2 | **If not provided**: Generate new certificate | `New-SelfSignedCertificate` with parameters below |

**Certificate Parameters** (new certificate):
```
Subject:           $CertificateSubject (default: CN=AuditWindowsCert)
CertStoreLocation: Cert:\CurrentUser\My
KeyExportPolicy:   Exportable
KeySpec:           Signature
KeyLength:         2048
KeyAlgorithm:      RSA
HashAlgorithm:     SHA256
NotAfter:          (Current date + $CertificateValidityInMonths months)
```

#### 9b. Certificate Export (Optional)

| Step | Action | Details |
|------|--------|---------|
| 9b.1 | Prompt for export skip | "Skip certificate file backup? (y/N)" |
| 9b.2a | **If not skipped**: Export .cer | `Export-Certificate -Type CERT` to `$USERPROFILE\AuditWindowsCert.cer` |
| 9b.2b | **If not skipped**: Export .pfx | `Export-PfxCertificate` with user-provided password to `$USERPROFILE\AuditWindowsCert.pfx` |

**Skipped if**: `-SkipCertificateExport` is specified.

#### 9c. Attach Certificate to Application

| Step | Action | Graph API |
|------|--------|-----------|
| 9c.1 | Check if certificate already attached | `Find-AuditWindowsKeyCredential` searches existing `KeyCredentials` |
| 9c.2 | **If not attached**: Add key credential | `Update-MgApplication -KeyCredentials @($keyCredential)` |

**KeyCredential Structure**:
```
Type:          AsymmetricX509Cert
Usage:         Verify
Key:           (certificate RawData)
DisplayName:   AuditWindows-{Thumbprint}
StartDateTime: Certificate NotBefore
EndDateTime:   Certificate NotAfter
```

**Outputs**: `$certificate` - Certificate object with `Thumbprint` and `NotAfter`.

---

### Phase 10: Output Summary and Cleanup

**Lines**: 156-185  
**Functions**: `New-AuditWindowsSummaryRecord`, `Write-AuditWindowsSummary`, `Disconnect-AuditWindowsGraph`

#### 10a. Create Summary Record

| Field | Value |
|-------|-------|
| `Timestamp` | Current date/time |
| `ApplicationId` | `$app.AppId` |
| `TenantId` | `$tenantId` |
| `CertificateThumbprint` | `$certificate.Thumbprint` or "N/A (interactive only)" |
| `CertificateExpiresOn` | `$certificate.NotAfter` or `[datetime]::MaxValue` |
| `LogoUploaded` | `$logoUploaded` |

#### 10b. Display and Export Summary

| Step | Action | Details |
|------|--------|---------|
| 10b.1 | Display summary to console | Application ID, Tenant ID, Certificate thumbprint, Logo status |
| 10b.2 | Export JSON summary | Writes to `$USERPROFILE\AuditWindowsAppSummary.json` (unless `-SkipSummaryExport`) |
| 10b.3 | Open Entra Portal | Launches browser to app's Credentials blade |

**Skipped if**: `-SkipSummaryExport` is specified.

#### 10c. Display Next Steps

| Message | Condition |
|---------|-----------|
| "Run Get-EntraWindowsDevices.ps1 to use this dedicated app with interactive auth" | Always |
| "Or use -UseAppAuth -TenantId '...' for certificate-based app-only auth" | If certificate was created |
| "Optionally configure Conditional Access policies targeting 'Audit Windows'" | Always |

#### 10d. Disconnect from Graph

**Function**: `Disconnect-AuditWindowsGraph`

| Step | Action | Details |
|------|--------|---------|
| 10d.1 | Disconnect Graph session | `Disconnect-MgGraph` |

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
| `TenantId` | string | - | Target tenant ID (uses authenticated context if not specified) |
| `Force` | switch | - | Skip all confirmation prompts |
| `Reauth` | switch | - | Force re-authentication |
| `SkipSummaryExport` | switch | - | Skip exporting summary JSON file |
| `SummaryOutputPath` | string | - | Custom path for summary JSON file |

---

## Files Created/Modified

| File | Location | Description |
|------|----------|-------------|
| `AuditWindowsAppSummary.json` | `$USERPROFILE` | JSON summary of provisioning |
| `AuditWindowsCert.cer` | `$USERPROFILE` | Public certificate (optional) |
| `AuditWindowsCert.pfx` | `$USERPROFILE` | Private certificate with password (optional) |
| Certificate | `Cert:\CurrentUser\My` | Self-signed certificate in Windows store |

---

## Error Handling

| Phase | Error Condition | Behavior |
|-------|-----------------|----------|
| 1 | PowerShell version < 7 | Throws exception, script exits |
| 1 | Missing modules/functions folder | Throws exception, script exits |
| 2 | Auth failed or cancelled | Throws exception, script exits |
| 4 | User types 'N' at confirmation | Throws "Operation cancelled by user." |
| 5 | Application creation fails | Throws exception with Graph error |
| 6 | Logo upload fails | Warns and continues (non-fatal) |
| 8 | Permission grant fails | Throws exception (requires admin role) |
| 9 | Certificate generation/attach fails | Throws exception |

---

## Required Azure AD Roles

One of the following roles is required for the authenticating user:

- **Global Administrator** — Full access
- **Application Administrator** — Can create apps and grant consent
- **Cloud Application Administrator** — Can create apps and grant consent (for non-privileged permissions)
