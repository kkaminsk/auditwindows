# Change Request: Windows Audit Application - Entra ID App Registration

## Document Information

| Field | Value |
|-------|-------|
| **Change Request ID** | CR-[YYYY-MM-DD]-[###] |
| **Submitted By** | [Your Name] |
| **Submission Date** | [YYYY-MM-DD] |
| **Tenant ID** | [Your Tenant GUID] |
| **Application Name** | WindowsAuditApp |
| **Priority** | [High / Medium / Low] |
| **Target Implementation Date** | [YYYY-MM-DD] |

---

## 1. Executive Summary

This change request seeks approval to create an Entra ID application registration named **WindowsAuditApp** to enable automated auditing of Windows devices in the organization. The application will use certificate-based authentication to query Microsoft Graph APIs and generate reports on device security posture (BitLocker, LAPS, Intune status).

---

## 2. Business Justification

- **Security Compliance**: Verify BitLocker recovery key backup and LAPS password availability across all Windows devices.
- **Operational Visibility**: Identify inactive devices, missing MDM enrollment, and configuration gaps.
- **Automation**: Enable scheduled, unattended reporting without interactive user authentication.
- **Audit Trail**: Maintain comprehensive logs of all device queries and security posture checks.

---

## 3. Scope

### 3.1 Application Registration Details

- **Application Name**: `WindowsAuditApp` (configurable via `-AppName` parameter)
- **Sign-in Audience**: `AzureADMyOrg` (single tenant)
- **Authentication Method**: Certificate-based (self-signed certificate created in `Cert:\CurrentUser\My`)
- **Service Principal**: Created automatically during provisioning

### 3.2 Certificate Management

- **Certificate Subject**: `CN=AuditWindowsCert` (configurable via `-CertificateSubject`)
- **Storage Location**: `Cert:\CurrentUser\My` (default) or `Cert:\LocalMachine\My` (for scheduled tasks)
- **Validity Period**: 24 months from creation (configurable 1-60 months)
- **Key Length**: 2048-bit RSA
- **Export Policy Options**:
  - **Exportable** (default): Can be backed up to `.pfx` file
  - **Non-Exportable** (`-NonExportable`): Private key cannot be exported, stronger security
  - **Azure Key Vault** (`-UseKeyVault`): Centralized, HSM-backed storage (recommended for production)

---

## 4. Required Permissions

### 4.1 Administrator Permissions (Provisioning Phase)

The administrator running the provisioning script (`-CreateAppIfMissing`) requires the following **delegated** Microsoft Graph permissions to create and configure the application:

| Permission | Type | Purpose |
|------------|------|---------|
| `Application.ReadWrite.All` | Delegated | Create and update the application registration |
| `AppRoleAssignment.ReadWrite.All` | Delegated | Grant application permissions (app roles) to the service principal |

**Required Azure AD Role** (one of the following):

| Role | Purpose |
|------|--------|
| **Application Administrator** | Create/manage app registrations and grant admin consent (Recommended) |
| **Cloud Application Administrator** | Same as above, but cannot manage on-premises apps |
| **Global Administrator** | Full access, if other roles are not available |

**Duration**: These permissions are only required during the initial provisioning or when updating application permissions. They are **not** required for subsequent report execution.

### 4.2 Application Permissions (Runtime)

Once provisioned, the application registration (`WindowsAuditApp`) requires the following **application** (app-only) permissions on **Microsoft Graph**.

**Required Azure AD Role to Run Get-EntraWindowsDevices.ps1** (one of the following):

| Role | Covers |
|------|--------|
| **Intune Administrator** | All permissions below (Recommended) |
| **Global Reader** | Device.Read.All, BitLockerKey.ReadBasic.All, DeviceLocalCredential.ReadBasic.All |
| **Security Reader** | Device.Read.All, BitLockerKey.ReadBasic.All |
| **Cloud Device Administrator** | Device.Read.All only |

**Application Permissions:**

| Permission | Type | Purpose | Risk Level |
|------------|------|---------|------------|
| `Device.Read.All` | Application | Read all device properties from Entra ID | Medium |
| `BitLockerKey.ReadBasic.All` | Application | Read BitLocker recovery key metadata (existence/backup status only; keys are not retrieved) | Medium |
| `DeviceLocalCredential.ReadBasic.All` | Application | Read LAPS password metadata (existence only; passwords are not retrieved) | Medium |
| `DeviceManagementManagedDevices.Read.All` | Application | Read Intune managed device data (last check-in, activity) | Medium |

**Admin Consent Required**: Yes. All application permissions require tenant administrator consent.

**Permissions Granted To**: Service Principal for `WindowsAuditApp`

**Resource**: Microsoft Graph

---

## 5. Security Considerations

### 5.1 Data Access

- **Sensitive Data**: The application can read BitLocker recovery key **metadata** and LAPS password **availability**. It does **not** retrieve actual recovery keys or passwords.
- **Read-Only**: All permissions are read-only. The application cannot modify devices, keys, or passwords.
- **Scope**: Access is limited to Windows devices in the tenant. No user data, emails, or files are accessed.

### 5.2 Authentication Security

- **Certificate-Based**: Uses a self-signed certificate instead of client secrets (secrets never expire accidentally and are more secure for automation).
- **Private Key Protection Options**:
  - **Exportable** (default): Stored in certificate store; can be backed up but vulnerable to extraction
  - **Non-Exportable** (`-NonExportable`): Private key cannot be exported, protecting against credential theft
  - **Azure Key Vault** (`-UseKeyVault`): HSM-backed storage with audit logging (recommended for production)
- **Certificate Store Locations**:
  - `Cert:\CurrentUser\My`: For interactive use only
  - `Cert:\LocalMachine\My`: For scheduled tasks and service accounts (requires admin)
- **No User Context**: Application runs with app-only permissions; no user sign-in required.
- **Certificate Health Monitoring**: Built-in expiration warnings (30-day default threshold)

### 5.3 Audit and Monitoring

- **Audit Logs**: All Graph API calls are logged in Entra ID sign-in logs under the service principal identity.
- **Script Logging**: Detailed logs written to `WindowsAudit-YYYY-MM-DD-HH-MM.log` with timestamps, operation names, and results.
- **No Secret Exposure**: BitLocker keys and LAPS passwords are never written to logs or console output.

### 5.4 Compliance

- **Least Privilege**: Application permissions are scoped to the minimum required for device auditing.
- **Time-Bound**: Certificate validity is 2 years; renewal is required before expiration.
- **Segregation of Duties**: Provisioning permissions (admin) are separate from runtime permissions (app).

---

## 6. Implementation Steps

### 6.1 Provisioning Option A: Dedicated App Registration (Recommended)

Use `Setup-AuditWindowsApp.ps1` to create a dedicated "Audit Windows" app registration with pre-consented permissions. This is the recommended approach for production use.

**Prerequisites:**
- PowerShell 7+
- Microsoft Graph PowerShell SDK installed (or auto-install enabled)
- Administrator account with Application Administrator or Global Administrator role
- Optional: `logo.jpg` in the script directory for app branding
- For Key Vault: `Az.Accounts` and `Az.KeyVault` modules, Azure authentication

**Command Options:**
```powershell
# Basic setup with exportable certificate (default)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -TenantId '<YOUR_TENANT_GUID>' -Force

# Non-exportable certificate (more secure, cannot be backed up)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -TenantId '<YOUR_TENANT_GUID>' -NonExportable -Force

# Azure Key Vault storage (recommended for production)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -TenantId '<YOUR_TENANT_GUID>' `
  -UseKeyVault -VaultName 'mykeyvault' -Force

# Auto-provision Key Vault and resource group
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -TenantId '<YOUR_TENANT_GUID>' `
  -UseKeyVault -VaultName 'auditwindows-kv' `
  -CreateVaultIfMissing -KeyVaultResourceGroupName 'auditwindows-rg' -KeyVaultLocation 'eastus' -Force

# LocalMachine store for scheduled tasks (requires admin)
pwsh -NoProfile -File .\Setup-AuditWindowsApp.ps1 -TenantId '<YOUR_TENANT_GUID>' `
  -CertificateStoreLocation LocalMachine -Force
```

**Actions Performed:**
1. Connect to Microsoft Graph with admin delegated auth
2. Create application registration "Audit Windows" if it doesn't exist
3. Upload logo.jpg if present in script directory
4. Configure the 4 required application permissions
5. Create service principal for the application
6. Grant admin consent for all permissions
7. Create/retrieve certificate (local store or Key Vault)
8. Add certificate to application keyCredentials
9. Output JSON summary to `Setup-AuditWindowsApp-{timestamp}.json`
10. Open Entra Portal to the app's credentials blade

**Usage after setup:**
```powershell
# Delegated auth using the dedicated app (interactive)
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1

# App-only auth using local certificate
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId '<YOUR_TENANT_GUID>'

# App-only auth using Key Vault certificate
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId '<YOUR_TENANT_GUID>' `
  -UseKeyVault -VaultName 'mykeyvault'
```

### 6.2 Provisioning Option B: Inline Provisioning (Legacy)

**Prerequisites:**
- PowerShell 7+
- Microsoft Graph PowerShell SDK installed (or auto-install enabled)
- Administrator account with permissions listed in section 4.1

**Command:**
```powershell
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 `
  -UseAppAuth `
  -CreateAppIfMissing `
  -TenantId '<YOUR_TENANT_GUID>' `
  -AppName 'WindowsAuditApp' `
  -CertSubject 'CN=WindowsAuditApp' `
  -MaxDevices 5 `
  -Verbose
```

**Actions Performed:**
1. Connect to Microsoft Graph with admin delegated auth (device code flow)
2. Create application registration `WindowsAuditApp` if it doesn't exist
3. Create service principal for the application
4. Create self-signed certificate `CN=WindowsAuditApp` in `Cert:\CurrentUser\My`
5. Add certificate public key to application `keyCredentials`
6. Grant required application permissions (section 4.2) to the service principal
7. Admin consent granted automatically during provisioning
8. Connect with app-only auth using the certificate
9. Run a test query (first 5 devices) to validate

### 6.3 Subsequent Execution (Automated/Scheduled)

**Prerequisites:**
- Certificate present in certificate store (`CurrentUser` or `LocalMachine`) or Azure Key Vault
- Application registration exists and has admin-consented permissions

**Command Options:**
```powershell
# Interactive auth (default)
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1

# App-only with local certificate
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId '<YOUR_TENANT_GUID>'

# App-only with Key Vault certificate
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId '<YOUR_TENANT_GUID>' `
  -UseKeyVault -VaultName 'mykeyvault'
```

**Actions Performed:**
1. Locate certificate in certificate store or Key Vault
2. Check certificate health (warns if expiring within 30 days)
3. Connect to Microsoft Graph using app-only auth (certificate)
4. Query all Windows devices from Entra ID
5. Enrich with Intune, BitLocker, and LAPS data
6. Write XML report and log to `%USERPROFILE%\Documents`

### 6.4 Download Key Vault Certificate to New Machine

When deploying to a new machine that needs to run scheduled tasks:

```powershell
# Interactive mode - select from JSON configs or browse Azure
.\Get-KeyVaultCertificateLocal.ps1

# Direct download to computer store (for scheduled tasks, requires admin)
.\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault'

# Download to user store (for interactive use only)
.\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault' -CurrentUser
```

---

## 7. Rollback Plan

### 7.1 Remove Application Registration

**Via Azure Portal:**
1. Navigate to **Entra ID** > **App registrations**
2. Search for `WindowsAuditApp`
3. Select the application
4. Click **Delete**
5. Confirm deletion (soft-deleted for 30 days; can be restored)

**Via PowerShell:**
```powershell
Connect-MgGraph -Scopes 'Application.ReadWrite.All'
$app = Get-MgApplication -Filter "displayName eq 'WindowsAuditApp'"
Remove-MgApplication -ApplicationId $app.Id
```

### 7.2 Remove Certificate

**Via Certificate Manager (CurrentUser):**
1. Open `certmgr.msc`
2. Navigate to **Personal** > **Certificates**
3. Locate certificate with subject `CN=AuditWindowsCert`
4. Right-click > **Delete**

**Via Certificate Manager (LocalMachine - requires admin):**
1. Open `certlm.msc`
2. Navigate to **Personal** > **Certificates**
3. Locate certificate with subject `CN=AuditWindowsCert`
4. Right-click > **Delete**

**Via PowerShell:**
```powershell
# Remove from CurrentUser store
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=AuditWindowsCert' } | Remove-Item

# Remove from LocalMachine store (requires admin)
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=AuditWindowsCert' } | Remove-Item
```

**Via Azure Key Vault:**
```powershell
# Delete certificate from Key Vault
Remove-AzKeyVaultCertificate -VaultName 'mykeyvault' -Name 'AuditWindowsCert'
```

### 7.3 Revoke Permissions

Permissions are automatically revoked when the application registration or service principal is deleted. No additional action required.

---

## 8. Testing and Validation

### 8.1 Provisioning Validation

- [ ] Application registration created in Entra ID
- [ ] Service principal exists and is enabled
- [ ] Certificate added to application `keyCredentials`
- [ ] All 4 application permissions granted with admin consent
- [ ] Test query returns expected device data

### 8.2 Runtime Validation

- [ ] Script connects successfully with app-only auth
- [ ] Windows devices retrieved from Entra ID
- [ ] BitLocker backup status detected correctly
- [ ] LAPS availability detected correctly
- [ ] XML report validates against `Demo.xsd`
- [ ] CSV export includes expected columns
- [ ] Logs written with no errors

### 8.3 Security Validation

- [ ] No BitLocker keys or LAPS passwords exposed in logs
- [ ] Graph API calls logged in Entra ID audit logs under service principal
- [ ] Certificate private key protected appropriately:
  - [ ] Non-exportable certificate cannot be extracted
  - [ ] Key Vault certificate has appropriate RBAC permissions
  - [ ] LocalMachine store requires admin access
- [ ] Application cannot write/modify devices or credentials
- [ ] Certificate health check warns when expiring soon

---

## 9. Post-Implementation

### 9.1 Certificate Management

- **Health Monitoring**: Use `Test-AuditWindowsCertificateHealth` to check certificate status:
  ```powershell
  $health = Test-AuditWindowsCertificateHealth -WarningDaysBeforeExpiry 30
  if (-not $health.Healthy) { Write-Warning $health.Message }
  ```
- **Renewal Reminder**: Set a calendar reminder for **[certificate validity - 30 days]** to renew before expiration. The script warns automatically when certificates are expiring.
- **Backup Options**:
  - **Exportable certificates**: Export to `.pfx` file:
    ```powershell
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=AuditWindowsCert' }
    $pwd = ConvertTo-SecureString -String 'YourSecurePassword' -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath 'C:\Secure\AuditWindowsCert.pfx' -Password $pwd
    ```
  - **Non-exportable certificates**: Re-run `Setup-AuditWindowsApp.ps1` to regenerate if lost
  - **Key Vault certificates**: Automatically backed up in Azure; download to new machines with `Get-KeyVaultCertificateLocal.ps1`

### 9.2 Scheduled Execution

- **Task Scheduler**: Create a scheduled task to run the script daily/weekly.
- **Certificate Store**: Use `LocalMachine` store for scheduled tasks:
  ```powershell
  # Setup with LocalMachine store
  .\Setup-AuditWindowsApp.ps1 -CertificateStoreLocation LocalMachine

  # Or download Key Vault cert to LocalMachine (requires admin)
  .\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault'
  ```
- **Service Account**: Can run as SYSTEM or any service account when using `Cert:\LocalMachine\My`.
- **Centralized Storage**: Configure `-OutputPath` to write reports to a shared network location or Azure Storage.

### 9.3 Monitoring

- **Log Monitoring**: Monitor `WindowsAudit-*.log` files for errors or warnings.
- **Report Review**: Schedule periodic review of XML/CSV reports to identify devices with missing BitLocker/LAPS.
- **Entra ID Audit**: Review sign-in logs for the service principal to detect anomalies.

---

## 10. Approval

### 10.1 Required Approvals

| Role | Name | Signature | Date |
|------|------|-----------|------|
| **IT Security Manager** | | | |
| **Identity & Access Management (IAM) Lead** | | | |
| **Compliance Officer** | | | |
| **IT Operations Manager** | | | |

### 10.2 Approval Criteria

- [ ] Business justification approved
- [ ] Security review completed and risks accepted
- [ ] Application permissions reviewed and approved
- [ ] Certificate management plan approved
- [ ] Rollback plan validated
- [ ] Testing plan approved

---

## 11. Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Unauthorized access to BitLocker keys/LAPS | High | Low | Application only reads **metadata** (existence), not actual keys/passwords. All API calls logged. |
| Certificate private key compromise | High | Low | Use non-exportable certificates or Azure Key Vault (HSM-backed) for production. LocalMachine store requires admin access. |
| Over-privileged application | Medium | Low | Least-privilege permissions; read-only access only. |
| Certificate expiration | Medium | Medium | Built-in health monitoring warns 30 days before expiry. Key Vault supports auto-renewal policies. |
| Service principal abuse | Medium | Low | Monitor Entra ID audit logs; alert on anomalous activity. Key Vault provides additional audit logging. |
| Key Vault access misconfiguration | Medium | Low | Requires explicit RBAC role assignment (Certificates Officer, Secrets User). |

---

## 12. References

- **Documentation**: `README.md` and `ApplicationSpecification.md` in the `auditwindows` repository
- **XSD Schema**: `Demo.xsd` for XML report validation
- **Microsoft Graph API**: [BitLocker Recovery Keys](https://learn.microsoft.com/en-us/graph/api/resources/bitlockerrecoverykey), [LAPS](https://learn.microsoft.com/en-us/graph/api/resources/devicelocalcredentialinfo)
- **Support**: Use the custom ChatGPT chatbot for assistance: https://chatgpt.com/g/g-68e6e364e48c8191993f38b9a190af02

---

## 13. Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.2 | 2025-11-26 | Kevin Kaminski | Added Key Vault integration, non-exportable certificates, LocalMachine store, certificate health monitoring |
| 1.0 | 2025-10-08 | Kevin Kaminski | Initial change request template |

---

## 14. Notes

- The provisioning script can be run multiple times safely; it will reuse existing application and certificate if present.
- For multi-tenant scenarios, adjust `-SignInAudience` and configure the application as `AzureADMultipleOrgs`.
- **Certificate Storage Recommendations**:
  - **Development/Testing**: Exportable certificate in `CurrentUser` store (default)
  - **Single-Machine Production**: Non-exportable certificate (`-NonExportable`)
  - **Multi-Machine/Enterprise**: Azure Key Vault (`-UseKeyVault`) with HSM backing (Premium SKU)
  - **Scheduled Tasks**: `LocalMachine` store (`-CertificateStoreLocation LocalMachine`)
- The script supports delegated (interactive) auth as an alternative to app-only for ad-hoc queries.
- Use `Get-KeyVaultCertificateLocal.ps1` to download Key Vault certificates to new machines for scheduled task deployment.
