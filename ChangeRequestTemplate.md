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

- **Certificate Subject**: `CN=WindowsAuditApp` (configurable via `-CertSubject`)
- **Storage Location**: `Cert:\CurrentUser\My` (user certificate store)
- **Validity Period**: 2 years from creation
- **Key Length**: 2048-bit RSA
- **Export Policy**: Exportable (for backup/transfer to automation systems)

---

## 4. Required Permissions

### 4.1 Administrator Permissions (Provisioning Phase)

The administrator running the provisioning script (`-CreateAppIfMissing`) requires the following **delegated** Microsoft Graph permissions to create and configure the application:

| Permission | Type | Purpose |
|------------|------|---------|
| `Application.ReadWrite.All` | Delegated | Create and update the application registration |
| `AppRoleAssignment.ReadWrite.All` | Delegated | Grant application permissions (app roles) to the service principal |
| `Directory.ReadWrite.All` | Delegated | Read directory objects and assign permissions |

**Recommended Azure AD Roles** (any one of):

For installation with Entra ID the user needs one of the following roles.

- **Application Administrator**
- **Cloud Application Administrator**
- **Global Administrator** (if other roles are not available)

**Duration**: These permissions are only required during the initial provisioning or when updating application permissions. They are **not** required for subsequent report execution.

### 4.2 Application Permissions (Runtime)

Once provisioned, the application registration (`WindowsAuditApp`) requires the following **application** (app-only) permissions on **Microsoft Graph**:

| Permission | Type | Purpose | Risk Level |
|------------|------|---------|------------|
| `Device.Read.All` | Application | Read all device properties from Entra ID | Medium |
| `Directory.Read.All` | Application | Read directory data (device metadata) | Medium |
| `BitLockerKey.Read.All` | Application | Read BitLocker recovery key metadata (existence/backup status only; keys are not retrieved) | **High** |
| `DeviceLocalCredential.Read.All` | Application | Read LAPS password metadata (existence only; passwords are not retrieved) | **High** |
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
- **Private Key Protection**: The certificate private key is stored in the user certificate store. For production automation, export and store in Azure Key Vault or a secure credential store.
- **No User Context**: Application runs with app-only permissions; no user sign-in required.

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

### 6.1 Provisioning (One-Time)

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

### 6.2 Subsequent Execution (Automated/Scheduled)

**Prerequisites:**
- Certificate present in `Cert:\CurrentUser\My` with subject `CN=WindowsAuditApp`
- Application registration exists and has admin-consented permissions

**Command:**
```powershell
pwsh -NoProfile -File .\Get-EntraWindowsDevices.ps1
```

**Actions Performed:**
1. Locate certificate in certificate store
2. Connect to Microsoft Graph using app-only auth (certificate)
3. Query all Windows devices from Entra ID
4. Enrich with Intune, BitLocker, and LAPS data
5. Write XML report and log to `%USERPROFILE%\Documents`

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

**Via Certificate Manager:**
1. Open `certmgr.msc`
2. Navigate to **Personal** > **Certificates**
3. Locate certificate with subject `CN=WindowsAuditApp`
4. Right-click > **Delete**

**Via PowerShell:**
```powershell
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=WindowsAuditApp' } | Remove-Item
```

### 7.3 Revoke Permissions

Permissions are automatically revoked when the application registration or service principal is deleted. No additional action required.

---

## 8. Testing and Validation

### 8.1 Provisioning Validation

- [ ] Application registration created in Entra ID
- [ ] Service principal exists and is enabled
- [ ] Certificate added to application `keyCredentials`
- [ ] All 5 application permissions granted with admin consent
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
- [ ] Certificate private key protected in user certificate store
- [ ] Application cannot write/modify devices or credentials

---

## 9. Post-Implementation

### 9.1 Certificate Management

- **Renewal Reminder**: Set a calendar reminder for **[2 years - 30 days]** to renew the certificate before expiration.
- **Backup**: Export the certificate (including private key) to a `.pfx` file and store in a secure location:
  ```powershell
  $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=WindowsAuditApp' }
  $pwd = ConvertTo-SecureString -String 'YourSecurePassword' -Force -AsPlainText
  Export-PfxCertificate -Cert $cert -FilePath 'C:\Secure\WindowsAuditApp.pfx' -Password $pwd
  ```

### 9.2 Scheduled Execution

- **Task Scheduler**: Create a scheduled task to run the script daily/weekly.
- **Service Account**: Use a dedicated service account with access to the certificate store.
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
| Certificate private key compromise | High | Low | Store in certificate store with ACLs; export to Azure Key Vault for production. |
| Over-privileged application | Medium | Low | Least-privilege permissions; read-only access only. |
| Certificate expiration | Medium | Medium | Set renewal reminder; monitor certificate validity. |
| Service principal abuse | Medium | Low | Monitor Entra ID audit logs; alert on anomalous activity. |

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
| 1.0 | 2025-10-08 | Kevin Kaminski | Initial change request template |

---

## 14. Notes

- The provisioning script can be run multiple times safely; it will reuse existing application and certificate if present.
- For multi-tenant scenarios, adjust `-SignInAudience` and configure the application as `AzureADMultipleOrgs`.
- If the organization uses Azure Key Vault for certificate storage, export the certificate and import to Key Vault after provisioning.
- The script supports delegated (interactive) auth as an alternative to app-only for ad-hoc queries.
