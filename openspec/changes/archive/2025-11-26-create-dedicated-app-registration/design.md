## Design: Dedicated App Registration for Audit Windows

### Goals
1. **Isolation**: Separate "Audit Windows" identity from shared Microsoft Graph PowerShell app
2. **Pre-consent**: Admin grants exactly 4 permissions upfront; no user self-consent
3. **Auditability**: Sign-ins to this app are clearly attributable to audit tool usage
4. **Flexibility**: Support both delegated (interactive) and app-only (certificate) flows

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Setup Phase (one-time, admin)                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Setup-AuditWindowsApp.ps1                               │   │
│  │  ├─ Connect with admin scopes                           │   │
│  │  ├─ Create/update "Audit Windows" app registration      │   │
│  │  ├─ Upload logo.jpg if present in script directory       │   │
│  │  ├─ Configure RequiredResourceAccess (4 permissions)    │   │
│  │  ├─ Grant admin consent via appRoleAssignment           │   │
│  │  ├─ Create/import certificate → keyCredentials          │   │
│  │  └─ Output JSON summary (AppId, TenantId, Thumbprint)   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Runtime Phase (operators)                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Get-EntraWindowsDevices.ps1                             │   │
│  │  ├─ -UseAppRegistration → look up "Audit Windows" app   │   │
│  │  │   └─ Connect-MgGraph -ClientId <AuditWindowsAppId>   │   │
│  │  ├─ -UseAppAuth → certificate auth (existing)           │   │
│  │  └─ (default) → Microsoft Graph PowerShell (unchanged)  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Permission Model

| Permission | Purpose | Type |
|------------|---------|------|
| `Device.Read.All` | Enumerate Windows devices | Application |
| `BitLockerKey.ReadBasic.All` | Read BitLocker key metadata | Application |
| `DeviceLocalCredential.ReadBasic.All` | Read LAPS availability | Application |
| `DeviceManagementManagedDevices.Read.All` | Read Intune managed device data | Application |

### File Structure

```
auditwindows/
├── Setup-AuditWindowsApp.ps1          # New: admin setup script
├── Get-EntraWindowsDevices.ps1        # Modified: add -UseAppRegistration
├── modules/
│   └── AuditWindows.Automation.psm1   # New: shared helpers
├── functions/
│   ├── Connect-AuditWindowsGraph.ps1  # New: admin auth for setup
│   ├── Set-AuditWindowsApplication.ps1
│   ├── Set-AuditWindowsLogo.ps1       # New: upload logo.jpg
│   ├── Set-AuditWindowsPermissions.ps1
│   ├── Grant-AuditWindowsConsent.ps1
│   ├── Set-AuditWindowsKeyCredential.ps1
│   └── Write-AuditWindowsSummary.ps1
├── logo.jpg                           # Optional: app branding
└── ...
```

### Key Decisions

1. **Separate setup script**: Keeps provisioning logic out of the main audit script; admins run once, operators run daily.

2. **Modeled after PortalFuse pattern**: Proven structure from `refscripts/` with:
   - Module for shared utilities (permission list, thumbprint helpers)
   - Functions folder for discrete operations
   - JSON summary output for operational records

3. **Backward compatible**: Default behavior unchanged; `-UseAppRegistration` opts in.

4. **No secrets in code**: Permissions defined in module; certificate stored in `Cert:\CurrentUser\My`.

### Conditional Access Example

Once the app exists, admins can create a Conditional Access policy:
- **Target**: "Audit Windows" application
- **Conditions**: Require MFA, block from untrusted locations
- **Grant**: Require compliant device
