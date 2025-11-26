# Setup-AuditWindowsApp.ps1 Execution Flow

This document describes the step-by-step execution flow of the `Setup-AuditWindowsApp.ps1` script.

---

## Overview

The script automates the creation of an Entra ID (Azure AD) application registration for the Audit Windows tool, including certificate-based authentication setup and admin consent for required Graph permissions.

---

## Execution Phases

### Phase 1: Initialization

| Step | Action | Details |
|------|--------|---------|
| 1.1 | **PowerShell Version Check** | Validates PowerShell 7+ is running; throws error if version < 7 |
| 1.2 | **Set Strict Mode** | Enables `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` |
| 1.3 | **Load Helper Module** | Imports `modules/AuditWindows.Automation.psm1` (shared utility functions) |
| 1.4 | **Load Functions** | Dot-sources all `.ps1` files from the `functions/` folder |
| 1.5 | **Install Graph Modules** | Checks for and installs if missing: `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications` |

### Phase 2: Authentication

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 2.1 | **Check Existing Session** | `Connect-AuditWindowsGraph` | Calls `Get-MgContext` to detect existing Graph session |
| 2.2 | **Handle Reauth Flag** | `Connect-AuditWindowsGraph` | If `-Reauth` specified, calls `Disconnect-MgGraph` first |
| 2.3 | **Interactive Login** | `Connect-AuditWindowsGraph` | If no session exists, calls `Connect-MgGraph` with scopes: `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All` |
| 2.4 | **Validate Context** | `Connect-AuditWindowsGraph` | Confirms authenticated account exists in context |

**Scopes Requested** (from `Get-AuditWindowsAdminScopes`):
- `Application.ReadWrite.All`
- `AppRoleAssignment.ReadWrite.All`

### Phase 3: User Confirmation

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 3.1 | **Display Configuration** | Main script | Shows target tenant, app name, and permissions to be granted |
| 3.2 | **Prompt for Confirmation** | `Confirm-AuditWindowsAction` | Prompts user with `(y/N)` unless `-Force` is specified |
| 3.3 | **Handle Cancellation** | `Confirm-AuditWindowsAction` | Throws exception if user enters anything other than `y` or `Y` |

### Phase 4: Application Registration

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 4.1 | **Check Existing App** | `Get-AuditWindowsApplication` | Queries `Get-MgApplication -Filter "displayName eq '$DisplayName'"` |
| 4.2a | **Create New App** | `Set-AuditWindowsApplication` | If not found, calls `New-MgApplication` with: |
| | | | - `DisplayName`: App name (default: "Audit Windows") |
| | | | - `SignInAudience`: `AzureADMyOrg` (single tenant) |
| | | | - `IsFallbackPublicClient`: `$true` |
| | | | - `PublicClient.RedirectUris`: `http://localhost`, `https://login.microsoftonline.com/common/oauth2/nativeclient` |
| 4.2b | **Update Existing App** | `Set-AuditWindowsApplication` | If found, checks and updates public client settings if missing |
| 4.3 | **Return App Object** | `Set-AuditWindowsApplication` | Returns refreshed application object via `Get-MgApplication` |

### Phase 5: Logo Upload (Optional)

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 5.1 | **Check for Logo** | `Set-AuditWindowsLogo` | Looks for `logo.jpg` in the script directory (`$PSScriptRoot`) |
| 5.2a | **Upload Logo** | `Set-AuditWindowsLogo` | If found, calls `Set-MgApplicationLogo -InFile $logoPath` |
| 5.2b | **Skip Logo** | `Set-AuditWindowsLogo` | If not found, displays warning and continues |
| 5.3 | **Return Status** | `Set-AuditWindowsLogo` | Returns `$true` if uploaded, `$false` otherwise |

### Phase 6: Service Principal Creation

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 6.1 | **Check Existing SP** | `Get-AuditWindowsServicePrincipal` | Queries `Get-MgServicePrincipal -Filter "appId eq '$AppId'"` |
| 6.2 | **Create SP if Missing** | `Get-AuditWindowsServicePrincipal` | If not found, calls `New-MgServicePrincipal -AppId $AppId` |
| 6.3 | **Return SP Object** | `Get-AuditWindowsServicePrincipal` | Returns service principal object |

### Phase 7: Permission Configuration

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 7.1 | **Get Graph SP** | `Set-AuditWindowsPermissions` | Retrieves Microsoft Graph service principal (AppId: `00000003-0000-0000-c000-000000000000`) |
| 7.2 | **Build Resource Access** | `Get-AuditWindowsGraphResourceAccess` | Maps permission names to Graph app role IDs |
| 7.3 | **Update App Permissions** | `Set-AuditWindowsPermissions` | Calls `Update-MgApplication -RequiredResourceAccess` |
| 7.4 | **Grant Admin Consent** | `Grant-AuditWindowsConsent` | For each permission, calls `New-MgServicePrincipalAppRoleAssignment` |

**Permissions Configured** (from `Get-AuditWindowsPermissionNames`):
- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

#### Grant-AuditWindowsConsent Details

| Step | Action | Details |
|------|--------|---------|
| 7.4.1 | **Get Existing Assignments** | `Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All` |
| 7.4.2 | **Check Each Permission** | Skips if `AppRoleId` already assigned to Graph resource |
| 7.4.3 | **Create Assignment** | `New-MgServicePrincipalAppRoleAssignment` with `PrincipalId`, `ResourceId`, `AppRoleId` |

### Phase 8: Certificate Configuration

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 8.1a | **Use Existing Cert** | `Set-AuditWindowsKeyCredential` | If `-ExistingCertificateThumbprint` provided, locates cert in `Cert:\CurrentUser\My` |
| 8.1b | **Generate New Cert** | `Set-AuditWindowsKeyCredential` | Otherwise, calls `New-SelfSignedCertificate` with: |
| | | | - Subject: `-CertificateSubject` (default: `CN=AuditWindowsCert`) |
| | | | - Store: `Cert:\CurrentUser\My` |
| | | | - KeyLength: 2048-bit RSA |
| | | | - HashAlgorithm: SHA256 |
| | | | - Validity: `-CertificateValidityInMonths` (default: 24 months) |
| 8.2 | **Export .cer** | `Set-AuditWindowsKeyCredential` | Exports public key to `%USERPROFILE%\AuditWindowsCert.cer` |
| 8.3 | **Export .pfx** | `Set-AuditWindowsKeyCredential` | Prompts for password, exports to `%USERPROFILE%\AuditWindowsCert.pfx` |
| 8.4 | **Check Existing Key** | `Find-AuditWindowsKeyCredential` | Checks if certificate already attached to application |
| 8.5 | **Attach Certificate** | `Set-AuditWindowsKeyCredential` | Calls `Update-MgApplication -KeyCredentials` with certificate data |

### Phase 9: Summary and Output

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 9.1 | **Create Summary** | `New-AuditWindowsSummaryRecord` | Builds object with: `ApplicationId`, `TenantId`, `CertificateThumbprint`, `CertificateExpiresOn`, `LogoUploaded` |
| 9.2 | **Display Summary** | `Write-AuditWindowsSummary` | Outputs summary to console |
| 9.3 | **Export JSON** | `Write-AuditWindowsSummary` | Writes summary to `%USERPROFILE%\AuditWindowsAppSummary.json` (unless `-SkipSummaryExport`) |
| 9.4 | **Open Entra Portal** | `Write-AuditWindowsSummary` | Opens browser to app credentials blade: `https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/{AppId}` |
| 9.5 | **Display Next Steps** | Main script | Shows guidance for using the app with `Get-EntraWindowsDevices.ps1` |

---

## Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        INITIALIZATION                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ PS7 Check    │→ │ Load Module  │→ │ Load Funcs   │→ │ Install Graph│ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        AUTHENTICATION                                    │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Connect-AuditWindowsGraph                                         │   │
│  │  → Check existing session (Get-MgContext)                         │   │
│  │  → Interactive login if needed (Connect-MgGraph)                  │   │
│  │  → Scopes: Application.ReadWrite.All, AppRoleAssignment.ReadWrite │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        CONFIRMATION                                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Confirm-AuditWindowsAction                                        │   │
│  │  → Display config (tenant, app name, permissions)                 │   │
│  │  → Prompt (y/N) unless -Force                                     │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                      APPLICATION REGISTRATION                            │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Set-AuditWindowsApplication                                       │   │
│  │  → Get-AuditWindowsApplication (check existing)                   │   │
│  │  → New-MgApplication OR Update-MgApplication                      │   │
│  │  → Configure: SignInAudience, PublicClient, RedirectUris          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                         LOGO UPLOAD                                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Set-AuditWindowsLogo                                              │   │
│  │  → Check for logo.jpg in script directory                        │   │
│  │  → Set-MgApplicationLogo if found                                 │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                      SERVICE PRINCIPAL                                   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Get-AuditWindowsServicePrincipal                                  │   │
│  │  → Get-MgServicePrincipal (check existing)                        │   │
│  │  → New-MgServicePrincipal if not found                            │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                     PERMISSIONS & CONSENT                                │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Set-AuditWindowsPermissions                                       │   │
│  │  → Get Microsoft Graph service principal                          │   │
│  │  → Get-AuditWindowsGraphResourceAccess (build permission map)     │   │
│  │  → Update-MgApplication -RequiredResourceAccess                   │   │
│  │                                                                   │   │
│  │ Grant-AuditWindowsConsent                                         │   │
│  │  → For each permission: New-MgServicePrincipalAppRoleAssignment   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                      CERTIFICATE SETUP                                   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Set-AuditWindowsKeyCredential                                     │   │
│  │  → Use existing OR New-SelfSignedCertificate                      │   │
│  │  → Export-Certificate (.cer)                                      │   │
│  │  → Export-PfxCertificate (.pfx) with password prompt              │   │
│  │  → Update-MgApplication -KeyCredentials                           │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                       SUMMARY & OUTPUT                                   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ New-AuditWindowsSummaryRecord → Build summary object              │   │
│  │ Write-AuditWindowsSummary                                         │   │
│  │  → Display to console                                             │   │
│  │  → Export to AuditWindowsAppSummary.json                          │   │
│  │  → Open Entra Portal (credentials blade)                          │   │
│  │ Display Next Steps                                                │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Output Artifacts

| Artifact | Location | Description |
|----------|----------|-------------|
| **Certificate** | `Cert:\CurrentUser\My` | Self-signed certificate in user certificate store |
| **Public Key (.cer)** | `%USERPROFILE%\AuditWindowsCert.cer` | Exportable public key file |
| **Private Key (.pfx)** | `%USERPROFILE%\AuditWindowsCert.pfx` | Password-protected private key file |
| **Summary JSON** | `%USERPROFILE%\AuditWindowsAppSummary.json` | Provisioning summary with AppId, TenantId, thumbprint |

---

## Error Handling

The script uses `$ErrorActionPreference = 'Stop'` and throws exceptions at key failure points:

| Phase | Error Condition | Action |
|-------|-----------------|--------|
| Initialization | PowerShell < 7 | `throw` with version message |
| Initialization | Module/functions not found | `throw` with path |
| Authentication | Login failed/cancelled | `throw` with error details |
| Confirmation | User enters non-`y` response | `throw "Operation cancelled by user."` |
| Permissions | Missing Graph app roles | `throw` with permission details |
| Consent | Insufficient privileges | `throw` with role requirements |
| Certificate | Thumbprint not found | `throw` with store path |
| Certificate | Attachment failed | `throw` with error details |

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `AppDisplayName` | string | `'Audit Windows'` | Display name for the app registration |
| `CertificateSubject` | string | `'CN=AuditWindowsCert'` | Subject for generated certificate |
| `CertificateValidityInMonths` | int | `24` | Certificate validity (1-60 months) |
| `ExistingCertificateThumbprint` | string | — | Use existing cert instead of generating |
| `TenantId` | string | — | Target tenant (uses context default if omitted) |
| `Force` | switch | `$false` | Skip confirmation prompts |
| `Reauth` | switch | `$false` | Force re-authentication |
| `SkipSummaryExport` | switch | `$false` | Don't write summary JSON file |
| `SummaryOutputPath` | string | — | Custom path for summary JSON |
