Perfect — I’ve reviewed **both** documents (`draft app spec audit windows.docx` and `windows specification questions.docx`) and can now merge and refine them into a **complete, production-ready application specification** with clarified requirements based on your answers.

Here’s the **refined, expanded specification** for the *Windows Audit Application*:

------

# 🧾 Windows Audit Application Specification (Finalized)

## 1. Overview

The **Windows Audit Application** is a PowerShell 7 script that connects to **Microsoft Graph** to retrieve and audit all **Windows devices in Entra ID**. It collects metadata, verifies BitLocker and LAPS backup status, records results in an XML report, and logs all activity for security auditing and operational troubleshooting.

## 2. Architecture Overview

### **Execution Flow**

1. **Connect to Microsoft Graph** using either interactive delegated authentication (`Connect-MgGraph`) or app-only certificate authentication (service principal). When app-only is selected and the app doesn’t exist, the script can provision it (admin consent required). If Microsoft.Graph cmdlets are not available, REST calls via `Invoke-MgGraphRequest` are used as a fallback.
2. **Query Entra ID devices** where `operatingSystem eq 'Windows'`.
3. **Collect key attributes** for each device:
   - Device Name
   - Device ID
   - Enabled status
   - User Principal Name
   - MDM authority
   - Activity status
   - Last Check-In time (from Intune ManagedDevice)
4. **Retrieve security attributes:**
   - BitLocker recovery keys by Azure AD `deviceId`; classify per-volume (OperatingSystem/Data), capture backup timestamp when available, and emit a per-drive `Encrypted` boolean (true when a key is backed up).
   - LAPS availability via GET-by-ID at `/directory/deviceLocalCredentials/{deviceId}` (existence only; no secrets).
5. **Generate XML report** containing all collected data.
6. **Log all actions and errors** to a timestamped log file.

### **Module Structure**

| Module                          | Purpose                                               |
| ------------------------------- | ----------------------------------------------------- |
| `Get-EntraWindowsDevices.ps1`   | Authenticates to Graph API (delegated or app-only).   |
| `Get-EntraWindowsDevices.ps1`   | Retrieves Entra ID devices with `OS = Windows`.       |
| `Get-EntraWindowsDevices.ps1`   | Queries BitLocker key protector info for each device. |
| ``Get-EntraWindowsDevices.ps1`` | Checks for LAPS credentials via Graph.                |
| ``Get-EntraWindowsDevices.ps1`` | Builds and writes XML output.                         |
| ``Get-EntraWindowsDevices.ps1`` | Handles structured logging and verbosity.             |

------
## 3. Permissions & Access Control

### **Required Graph API Scopes**

- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `Directory.Read.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

### **Recommended Azure Roles**

- **Global Reader**, or
- **Intune Administrator**, or
- **Security Reader**

### **Authentication Methods**

- **Delegated (interactive)**: default; supports `-UseDeviceCode` for device code flow.
- **App-only (certificate)**: enable with `-UseAppAuth`; requires `-TenantId`. If `-CreateAppIfMissing` is set, the script will:
  - Create an application and service principal (display name from `-AppName`, default `WindowsAuditApp`).
  - Create or reuse a self-signed certificate in `Cert:\CurrentUser\My` (subject from `-CertSubject`, default `CN=<AppName>`).
  - Add the certificate to the application `keyCredentials`.
  - Grant required Graph application permissions on the Microsoft Graph service principal.
  - Connect app-only using certificate.

------

## 5. XML Schema Design

### **Schema Structure**

```xml
<WindowsAudit>
  <Device>
    <Name>PC-123</Name>
    <DeviceID>xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx</DeviceID>
    <AzureAdDeviceId>yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy</AzureAdDeviceId>
    <Enabled>true</Enabled>
    <UserPrincipalName>user@domain.com</UserPrincipalName>
    <MDM>Microsoft Intune</MDM>
    <Activity>Active</Activity>
    <LastCheckIn>2025-10-06T22:41:00Z</LastCheckIn>
    <BitLocker>
      <Drive type="OperatingSystem">
        <BackedUp>2025-10-07T13:15:00Z</BackedUp>
        <Encrypted>true</Encrypted>
      </Drive>
      <Drive type="Data">
        <BackedUp>false</BackedUp>
        <Encrypted>false</Encrypted>
      </Drive>
    </BitLocker>
    <LAPS>
      <Available>true</Available>
      <Retrieved>false</Retrieved>
    </LAPS>
  </Device>
</WindowsAudit>
```

### **Behavior**

- One **consolidated XML file** for all Windows devices.
- Devices missing BitLocker or LAPS data will have:

```xml
<BitLocker>
  <Drive type="OperatingSystem">
    <BackedUp>false</BackedUp>
  </Drive>
</BitLocker>
<LAPS>
  <Available>false</Available>
</LAPS>
```

- XML saved alongside the log unless `-OutputPath` overrides it.

- For BitLocker, `Encrypted` is `true` when a recovery key exists in Entra for that drive (i.e., a backup timestamp or presence is detected). It does not probe device-local encryption state.

------

## 6. Error Handling & Resilience

- **Retry policy** on Graph API throttling (`Retry-After` header respected).
- **Graceful skip** of devices missing required attributes.
- **Continue on error** — no termination on transient failures.
- **Error entries** logged with timestamp and exception detail.
- **404 NotFound** for BitLocker or LAPS treated as non-fatal (interpreted as “no data”).
- **REST fallback** is used when Microsoft.Graph cmdlets are unavailable to avoid module assembly conflicts.

------

## 7. Output Options

| Parameter              | Description                                                |
| ---------------------- | ---------------------------------------------------------- |
| `-OutputPath <path>`   | Override default report directory.                         |
| `-ExportCSV`           | Creates an additional CSV summary of key device properties.|
| `-Verbose`             | Enables verbose mode logging (see above).                  |
| `-UseDeviceCode`       | Use device code flow for delegated authentication.         |
| `-MaxDevices <n>`      | Process only the first N devices (for testing).           |
| `-UseAppAuth`          | Use app-only certificate authentication.                  |
| `-CreateAppIfMissing`  | Provision the app registration if not present.            |
| `-AppName <name>`      | App registration display name (default: WindowsAuditApp). |
| `-TenantId <guid>`     | Tenant to connect with app-only auth.                     |
| `-CertSubject <dn>`    | Cert subject for self-signed cert (default: CN=<AppName>).|
| `-SkipModuleImport`    | Skip importing Microsoft.Graph modules and use REST fallbacks. |
| `-DeviceName <name>`   | Process only devices with matching `DisplayName`.         |

Default output directory:

```
%USERPROFILE%\Documents\
```

### CSV columns

- Includes `BitLockerOSEncrypted` and `BitLockerDataEncrypted` in addition to existing fields.

------

## 8. Security & Data Handling

- LAPS passwords and BitLocker keys are **never printed to console or logs**.
- Only existence and backup status are recorded.
- XML report excludes sensitive secret values.
- When using app-only auth, a certificate is created/stored in `Cert:\CurrentUser\My` (unless provided). Handle the private key securely; consider exporting to a secure store if used in automation.

------

## 9. Future Expansion

- Add **Defender for Endpoint** status integration.
- Add **Compliance policy status** (Intune).
- Pull full **ManagedDevice** data for richer reporting.
- Optional **HTML report generator** for easy review.
- Package as a **PowerShell module**, integrate with **Azure Key Vault** for certificate storage, and support **managed identity** where feasible.

------

## 10. Intended Use Cases

- **Security Auditing** — verify BitLocker and LAPS posture across all Windows devices.
- **Operational Troubleshooting** — identify stale or inactive devices, missing backups, or misconfigurations.