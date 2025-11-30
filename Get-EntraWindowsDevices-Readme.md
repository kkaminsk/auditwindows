# Get-EntraWindowsDevices

Queries Windows devices from Microsoft Entra ID (Azure AD) and retrieves security audit information including BitLocker recovery keys and LAPS availability.

## Prerequisites

- PowerShell 7.0 or later
- Microsoft Graph PowerShell SDK modules (installed automatically)
- Appropriate permissions (see Authentication Methods below)

## Quick Start

```powershell
# Interactive authentication (simplest)
.\Get-EntraWindowsDevices.ps1

# App-only authentication with local certificate
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId 'contoso.onmicrosoft.com'

# App-only authentication with Key Vault certificate
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId 'contoso.onmicrosoft.com' -UseKeyVault -VaultName 'mykeyvault'
```

## Authentication Methods

### 1. Interactive Authentication (Default)

Uses delegated permissions with your user account. Best for ad-hoc queries.

```powershell
.\Get-EntraWindowsDevices.ps1
```

### 2. Device Code Authentication

For environments where browser pop-ups aren't available.

```powershell
.\Get-EntraWindowsDevices.ps1 -UseDeviceCode
```

### 3. App-Only Authentication (Certificate)

Uses application permissions with a certificate. Best for automation and scheduled tasks.

**Setup (one-time):**
```powershell
# Create the app registration and certificate
.\Setup-AuditWindowsApp.ps1
```

**Usage:**
```powershell
# With local certificate (uses certificate subject to find cert)
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId 'contoso.onmicrosoft.com'

# With specific certificate subject
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId 'contoso.onmicrosoft.com' -CertSubject 'CN=MyCert'
```

### 4. App-Only Authentication with Azure Key Vault

Uses a certificate stored in Azure Key Vault. Best for enterprise environments with centralized secret management.

**Setup (one-time):**
```powershell
# Create app registration with Key Vault certificate storage
.\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'mykeyvault'
```

**Usage:**
```powershell
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId 'contoso.onmicrosoft.com' -UseKeyVault -VaultName 'mykeyvault'
```

**Download certificate to a new machine:**
```powershell
# Use this utility to download the Key Vault certificate to your local store
.\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault'
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-OutputPath` | String | Custom output directory for reports. Default: My Documents |
| `-ExportCSV` | Switch | Also export results to CSV format |
| `-UseDeviceCode` | Switch | Use device code flow for authentication |
| `-MaxDevices` | Int | Limit the number of devices to process |
| `-UseAppAuth` | Switch | Use app-only (certificate) authentication |
| `-TenantId` | String | Tenant ID (required with `-UseAppAuth`) |
| `-CertSubject` | String | Certificate subject for local cert auth |
| `-UseKeyVault` | Switch | Use Azure Key Vault for certificate |
| `-VaultName` | String | Key Vault name (required with `-UseKeyVault`) |
| `-KeyVaultCertificateName` | String | Certificate name in Key Vault. Default: 'AuditWindowsCert' |
| `-DeviceName` | String | Filter to a specific device by name |
| `-SkipCertificateHealthCheck` | Switch | Skip certificate expiration warnings |
| `-SkipModuleImport` | Switch | Skip automatic module installation |
| `-AppName` | String | App registration name. Default: 'WindowsAuditApp' |
| `-AppDisplayName` | String | App display name. Default: 'Audit Windows' |
| `-CreateAppIfMissing` | Switch | Auto-create app registration if not found |

## Output Files

The script generates files in the output directory (default: My Documents):

| File | Description |
|------|-------------|
| `WindowsAudit-{timestamp}.xml` | Full audit data in XML format |
| `WindowsAudit-{timestamp}.csv` | Summary data (if `-ExportCSV` specified) |
| `WindowsAudit-{timestamp}.log` | Detailed execution log |

## Examples

### Export all Windows devices

```powershell
.\Get-EntraWindowsDevices.ps1 -ExportCSV
```

### Query a specific device

```powershell
.\Get-EntraWindowsDevices.ps1 -DeviceName 'DESKTOP-ABC123'
```

### Limit to first 10 devices (for testing)

```powershell
.\Get-EntraWindowsDevices.ps1 -MaxDevices 10
```

### Export to custom location

```powershell
.\Get-EntraWindowsDevices.ps1 -OutputPath 'C:\AuditReports' -ExportCSV
```

### Automated scheduled task with Key Vault

**One-time setup (run as Administrator):**
```powershell
# Download certificate to computer store for scheduled task access
.\Get-KeyVaultCertificateLocal.ps1 -VaultName 'audit-keyvault' -LocalMachine
```

**Scheduled task command:**
```powershell
# Non-interactive, uses Key Vault certificate from LocalMachine store
.\Get-EntraWindowsDevices.ps1 `
    -UseAppAuth `
    -TenantId 'contoso.onmicrosoft.com' `
    -UseKeyVault `
    -VaultName 'audit-keyvault' `
    -OutputPath 'C:\ScheduledReports' `
    -ExportCSV
```

**Note:** The scheduled task can run as SYSTEM or any service account since the certificate is in `Cert:\LocalMachine\My`.

## Key Vault Certificate Setup

### Required Azure RBAC Roles

To use Key Vault certificate storage, you need these roles on the Key Vault:

| Role | Purpose |
|------|---------|
| Key Vault Certificates Officer | Create and manage certificates |
| Key Vault Secrets User | Download certificate with private key |

### Download Certificate to New Machine

When setting up a new machine that needs to run the script with app-only auth:

```powershell
# For interactive use - download to current user's store
.\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault'

# For scheduled tasks/services - download to computer store (requires Admin)
.\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault' -LocalMachine

# Then run the audit
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId 'contoso.onmicrosoft.com' -UseKeyVault -VaultName 'mykeyvault'
```

### Certificate Store Locations

| Store | Path | Use Case |
|-------|------|----------|
| User Store | `Cert:\CurrentUser\My` | Interactive execution as logged-in user |
| Computer Store | `Cert:\LocalMachine\My` | Scheduled tasks, services, non-interactive automation |

**Important:** For scheduled tasks running as SYSTEM or a service account, the certificate **must** be in the LocalMachine store, as the CurrentUser store is not accessible when no user is logged in.

### Certificate Rotation

When the certificate in Key Vault is rotated:

1. The new certificate is automatically used on next run
2. Use `Get-KeyVaultCertificateLocal.ps1` to download the new certificate to machines that cache it locally
3. Update the app registration if the certificate thumbprint changed (handled by `Setup-AuditWindowsApp.ps1`)

## Troubleshooting

### Access Denied to Key Vault

```
Access denied to Key Vault 'myvault'.
Required RBAC roles:
  - Key Vault Certificates Officer
  - Key Vault Secrets User
```

**Solution:** Assign the required roles in Azure Portal:
1. Go to Key Vault → Access control (IAM)
2. Add role assignment for both roles
3. Wait 2-3 minutes for propagation

### Certificate Not Found

```
Certificate 'AuditWindowsCert' not found in Key Vault
```

**Solution:** Run `Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'myvault'` to create the certificate.

### Certificate Expiring Soon

The script warns when certificates expire within 90 days. To renew:

```powershell
# Re-run setup to generate a new certificate
.\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'myvault'
```

### App Registration Not Found

```
Application 'Audit Windows' not found
```

**Solution:** Run `Setup-AuditWindowsApp.ps1` to create the app registration.

## Related Scripts

| Script | Purpose |
|--------|---------|
| `Setup-AuditWindowsApp.ps1` | Create app registration and certificate |
| `Get-KeyVaultCertificateLocal.ps1` | Download Key Vault certificate to local store |

## Security Considerations

- **App-only authentication** is recommended for automated/scheduled execution
- **Key Vault storage** provides centralized certificate management with audit logging
- Certificates are created as **non-exportable** by default when using local storage
- Grant **minimum required permissions** to the app registration
- Use **Conditional Access policies** to restrict app access if needed
