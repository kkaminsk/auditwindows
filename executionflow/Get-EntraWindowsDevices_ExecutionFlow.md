# Get-EntraWindowsDevices.ps1 Execution Flow

This document describes the step-by-step execution flow of the `Get-EntraWindowsDevices.ps1` script, which audits Windows devices from Entra ID and reports on BitLocker and LAPS security posture.

---

## Overview

The script connects to Microsoft Graph, enumerates all Windows devices from Entra ID, enriches each device with Intune, BitLocker, and LAPS data, then outputs results to XML (and optionally CSV) reports.

**Total Phases**: 7  
**Estimated Duration**: Varies by device count (1-2 seconds per device)

---

## Execution Flow

### Phase 1: Initialization and Setup

**Lines**: 1-33

| Step | Action | Details |
|------|--------|---------|
| 1.1 | Verify PowerShell 7+ | `#Requires -Version 7.0` directive |
| 1.2 | Parse parameters | Accept `OutputPath`, `ExportCSV`, `UseDeviceCode`, `MaxDevices`, `UseAppAuth`, etc. |
| 1.3 | Initialize timestamps | `$start = Get-Date`, generate timestamp string `yyyy-MM-dd-HH-mm` |
| 1.4 | Set output paths | Default to `%USERPROFILE%\Documents` or use `-OutputPath` |
| 1.5 | Create output directory | `New-Item -ItemType Directory` if path doesn't exist |
| 1.6 | Initialize file paths | Set `$logPath`, `$xmlPath`, `$csvPath` with timestamp |
| 1.7 | Load functions | Dot-source all `.ps1` files from `.\functions` folder |
| 1.8 | Write initial log | `Write-Log "Script start. OutputPath=$docs"` |

**Output Files Initialized**:
```
WindowsAudit-YYYY-MM-DD-HH-MM.log
WindowsAudit-YYYY-MM-DD-HH-MM.xml
WindowsAudit-YYYY-MM-DD-HH-MM.csv (if -ExportCSV)
```

---

### Phase 2: Load Microsoft Graph Modules

**Lines**: 40-45  
**Function**: `Import-GraphModuleIfNeeded`

| Step | Action | Details |
|------|--------|---------|
| 2.1 | Check if commands already available | Skips import if all required cmdlets exist |
| 2.2 | Determine required modules | Base: Authentication, DirectoryManagement, DeviceManagement |
| 2.3 | Add app modules if needed | Applications, ServicePrincipals (only for `-UseAppAuth`) |
| 2.4 | Install missing modules | `Install-Module -Scope CurrentUser` if not available |
| 2.5 | Import modules | `Import-Module` with fallback to REST if import fails |

**Modules Loaded**:
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Identity.DirectoryManagement`
- `Microsoft.Graph.DeviceManagement`
- `Microsoft.Graph.Applications` (if `-UseAppAuth`)
- `Microsoft.Graph.ServicePrincipals` (if `-UseAppAuth`)

**Bypass**: Use `-SkipModuleImport` to rely on REST fallback via `Invoke-MgGraphRequest`.

---

### Phase 3: Connect to Microsoft Graph

**Lines**: 46-51

Two authentication paths based on `-UseAppAuth` parameter:

#### Path A: Delegated (Interactive) Authentication

**Function**: `Connect-GraphInteractive`

| Step | Action | Graph API |
|------|--------|-----------|
| 3A.1 | Connect with read scope | `Connect-MgGraph -Scopes 'Application.Read.All'` |
| 3A.2 | Search for "Audit Windows" app | `Get-MgServicePrincipal -Filter "displayName eq 'Audit Windows'"` |
| 3A.3 | Validate app exists | If not found, display error and exit with instructions |
| 3A.4 | Disconnect lookup session | `Disconnect-MgGraph` |
| 3A.5 | Connect with audit scopes | `Connect-MgGraph -TenantId -ClientId -Scopes` |

**Required Scopes** (delegated):
- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

#### Path B: App-Only (Certificate) Authentication

**Function**: `Initialize-AppRegistrationAndConnect`

| Step | Action | Details |
|------|--------|---------|
| 3B.1 | Validate `-TenantId` provided | Throws if missing |
| 3B.2 | **If `-CreateAppIfMissing`**: Provision app | Admin auth → Create app → Create SP → Create cert → Grant permissions |
| 3B.3 | Locate certificate | `Get-ChildItem Cert:\CurrentUser\My` by subject |
| 3B.4 | Find application | `Get-MgApplication -Filter "displayName eq '$AppName'"` |
| 3B.5 | Connect with certificate | `Connect-MgGraph -TenantId -ClientId -CertificateThumbprint` |

**Required Permissions** (application):
- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

---

### Phase 4: Query Windows Devices

**Lines**: 53-68  
**Function**: `Get-WindowsDirectoryDevices`

| Step | Action | Graph API |
|------|--------|-----------|
| 4.1 | Log authentication context | `Get-MgContext` → log AuthType, TenantId, ClientId, Account |
| 4.2 | Query all Windows devices | `GET /devices?$filter=operatingSystem eq 'Windows'` |
| 4.3 | Filter by device name (optional) | If `-DeviceName` specified, filter results |
| 4.4 | Limit device count (optional) | If `-MaxDevices` specified, take first N devices |
| 4.5 | Log device count | "Retrieved X Windows devices." |

**Graph Query**:
```
GET /devices
  ?$select=id,displayName,deviceId,accountEnabled,operatingSystem
  &$filter=operatingSystem eq 'Windows'
```

**Device Properties Retrieved**:
| Property | Description |
|----------|-------------|
| `Id` | Directory object ID |
| `DeviceId` | Azure AD device ID (used for BitLocker/LAPS lookups) |
| `DisplayName` | Device name |
| `AccountEnabled` | Whether device is enabled |
| `OperatingSystem` | Always "Windows" (filtered) |

---

### Phase 5: Initialize XML Report

**Lines**: 70-72  
**Function**: `New-AuditXml`

| Step | Action | Details |
|------|--------|---------|
| 5.1 | Create XML document | `New-Object System.Xml.XmlDocument` |
| 5.2 | Add XML declaration | `<?xml version="1.0" encoding="UTF-8"?>` |
| 5.3 | Create root element | `<WindowsAudit>` |
| 5.4 | Initialize summary array | `$summary = @()` for CSV output |

---

### Phase 6: Process Each Device (Main Loop)

**Lines**: 74-143

For each device, the script performs enrichment queries and builds the XML/CSV output.

```
┌─────────────────────────────────────────────────────────────────┐
│                    FOR EACH DEVICE                               │
└─────────────────────────────────────────────────────────────────┘
                                │
         ┌──────────────────────┼──────────────────────┐
         ▼                      ▼                      ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ 6a. Get Intune  │   │ 6b. Get BitLocker│   │ 6c. Check LAPS │
│ Managed Device  │   │ Recovery Keys    │   │ Availability   │
└─────────────────┘   └─────────────────┘   └─────────────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                                ▼
                  ┌─────────────────────────┐
                  │ 6d. Build XML/CSV Entry │
                  └─────────────────────────┘
```

#### 6a. Get Intune Managed Device

**Function**: `Get-ManagedDeviceByAadId`

| Step | Action | Graph API |
|------|--------|-----------|
| 6a.1 | Query by Azure AD device ID | `GET /deviceManagement/managedDevices?$filter=azureADDeviceId eq '{id}'` |
| 6a.2 | Extract properties | `UserPrincipalName`, `LastSyncDateTime` |
| 6a.3 | Calculate activity status | Active if LastSyncDateTime < 30 days ago |

**Properties Retrieved**:
| Property | Description |
|----------|-------------|
| `UserPrincipalName` | Primary user of the device |
| `LastSyncDateTime` | Last Intune check-in time |

#### 6b. Get BitLocker Recovery Keys

**Function**: `Get-BitLockerKeysByDeviceId`

| Step | Action | Graph API |
|------|--------|-----------|
| 6b.1 | Query by Azure AD device ID | `GET /informationProtection/bitlocker/recoveryKeys?$filter=deviceId eq '{id}'` |
| 6b.2 | If not found, try Object ID | Fallback lookup with directory object ID |
| 6b.3 | Parse key metadata | Extract `VolumeType`, `CreatedDateTime` |
| 6b.4 | Classify volume types | OS drive vs Data drive |

**Volume Type Classification**:
| VolumeType Value | Classification |
|------------------|----------------|
| `operatingSystemVolume`, `operatingSystemDrive`, `os`, `1`, `null` | OS Drive |
| `fixedDataVolume`, `fixedDataDrive`, `data`, `2` | Data Drive |

**Note**: Only metadata is retrieved; actual recovery keys are never accessed.

#### 6c. Check LAPS Availability

**Function**: `Test-LapsAvailable`

| Step | Action | Graph API |
|------|--------|-----------|
| 6c.1 | Query LAPS credentials | `GET /directory/deviceLocalCredentials?$filter=deviceName eq '{name}'` |
| 6c.2 | Check if result exists | Returns `$true` if credentials found |

**Note**: Only checks existence; passwords are never retrieved.

#### 6d. Build XML and CSV Entry

**Functions**: `Add-TextNode` (XML helper)

| Step | Action | Details |
|------|--------|---------|
| 6d.1 | Create `<Device>` element | Append to `<WindowsAudit>` root |
| 6d.2 | Add device properties | Name, DeviceID, AzureAdDeviceId, Enabled, UserPrincipalName, MDM, Activity, LastCheckIn |
| 6d.3 | Add `<BitLocker>` section | `<Drive type="OperatingSystem">` and `<Drive type="Data">` |
| 6d.4 | Add `<LAPS>` section | `<Available>` and `<Retrieved>` |
| 6d.5 | Add to summary array | PSCustomObject for CSV export |
| 6d.6 | Display progress | `Write-Progress` with percentage |

**XML Structure per Device**:
```xml
<Device>
  <Name>DESKTOP-ABC123</Name>
  <DeviceID>xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx</DeviceID>
  <AzureAdDeviceId>yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy</AzureAdDeviceId>
  <Enabled>True</Enabled>
  <UserPrincipalName>user@contoso.com</UserPrincipalName>
  <MDM>Microsoft Intune</MDM>
  <Activity>Active</Activity>
  <LastCheckIn>2025-01-15T10:30:00.0000000Z</LastCheckIn>
  <BitLocker>
    <Drive type="OperatingSystem">
      <BackedUp>2024-06-01T08:00:00.0000000Z</BackedUp>
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
```

---

### Phase 7: Write Output and Complete

**Lines**: 145-150

| Step | Action | Details |
|------|--------|---------|
| 7.1 | Save XML report | `$xml.Save($xmlPath)` |
| 7.2 | Export CSV (optional) | `$summary \| Export-Csv` if `-ExportCSV` specified |
| 7.3 | Calculate duration | `(Get-Date) - $start` |
| 7.4 | Write completion log | "Script end. Duration={X}s" |
| 7.5 | Display completion | "Completed. Duration={X}s" |

**Output Files**:
| File | Condition | Content |
|------|-----------|---------|
| `WindowsAudit-*.xml` | Always | Full device audit with BitLocker/LAPS |
| `WindowsAudit-*.csv` | `-ExportCSV` | Flat summary for spreadsheet analysis |
| `WindowsAudit-*.log` | Always | Timestamped execution log |

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                   Get-EntraWindowsDevices.ps1                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Initialization                                          │
│   • Parse parameters                                             │
│   • Set output paths (Documents or -OutputPath)                  │
│   • Load functions from .\functions                             │
│   • Initialize log file                                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 2: Import-GraphModuleIfNeeded                              │
│   • Check if cmdlets already available                           │
│   • Install/Import Microsoft.Graph.* submodules                  │
│   • Skip if -SkipModuleImport (uses REST fallback)              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3: Connect to Microsoft Graph                              │
│   ┌───────────────────┐       ┌───────────────────┐             │
│   │ -UseAppAuth?      │──No──▶│ Connect-Graph     │             │
│   │                   │       │ Interactive       │             │
│   └───────────────────┘       │ (delegated)       │             │
│          │Yes                 └───────────────────┘             │
│          ▼                                                       │
│   ┌───────────────────┐                                         │
│   │ Initialize-App    │                                         │
│   │ Registration      │                                         │
│   │ AndConnect        │                                         │
│   │ (certificate)     │                                         │
│   └───────────────────┘                                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 4: Get-WindowsDirectoryDevices                             │
│   • Query: GET /devices?$filter=operatingSystem eq 'Windows'    │
│   • Optional: Filter by -DeviceName                              │
│   • Optional: Limit by -MaxDevices                               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 5: New-AuditXml                                            │
│   • Create XML document with <WindowsAudit> root                │
│   • Initialize summary array for CSV                             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 6: Process Each Device                                     │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ FOR EACH device IN devices:                              │   │
│   │   • Get-ManagedDeviceByAadId (Intune data)              │   │
│   │   • Get-BitLockerKeysByDeviceId (key metadata)          │   │
│   │   • Test-LapsAvailable (LAPS check)                     │   │
│   │   • Build <Device> XML element                          │   │
│   │   • Add to $summary array                               │   │
│   │   • Write-Progress                                      │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 7: Write Output                                            │
│   • Save XML to WindowsAudit-*.xml                              │
│   • Export CSV (if -ExportCSV)                                  │
│   • Log completion with duration                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `OutputPath` | string | `%USERPROFILE%\Documents` | Directory for output files |
| `ExportCSV` | switch | - | Also export CSV summary |
| `UseDeviceCode` | switch | - | Use device code flow for auth |
| `MaxDevices` | int | - | Limit number of devices processed |
| `UseAppAuth` | switch | - | Use certificate-based app-only auth |
| `CreateAppIfMissing` | switch | - | Provision app registration if not found |
| `AppName` | string | `'WindowsAuditApp'` | App registration name (for -UseAppAuth) |
| `AppDisplayName` | string | `'Audit Windows'` | App display name for lookup |
| `TenantId` | string | - | Target tenant (required for -UseAppAuth) |
| `CertSubject` | string | - | Certificate subject for app-only auth |
| `SkipModuleImport` | switch | - | Skip module imports, use REST fallback |
| `DeviceName` | string | - | Filter to single device by name |

---

## Graph API Calls Summary

| Phase | Endpoint | Method | Purpose |
|-------|----------|--------|---------|
| 3 | `/servicePrincipals` | GET | Find "Audit Windows" app |
| 4 | `/devices` | GET | List all Windows devices |
| 6a | `/deviceManagement/managedDevices` | GET | Get Intune device info |
| 6b | `/informationProtection/bitlocker/recoveryKeys` | GET | Get BitLocker key metadata |
| 6c | `/directory/deviceLocalCredentials` | GET | Check LAPS availability |

---

## Error Handling

All Graph API calls use `Invoke-GraphWithRetry` which provides:

| Feature | Details |
|---------|---------|
| **Retry logic** | Up to 4 retries for 429, 502, 503, 504 errors |
| **Exponential backoff** | Wait time doubles each retry (max 60s) |
| **Retry-After header** | Honors throttling header if present |
| **Non-fatal errors** | 404 for BitLocker/LAPS treated as "not found" (not error) |
| **Detailed logging** | Each attempt logged with operation name, resource, elapsed time |

---

## Output Schema

### XML Report (`WindowsAudit-*.xml`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<WindowsAudit>
  <Device>
    <Name>string</Name>
    <DeviceID>guid</DeviceID>
    <AzureAdDeviceId>guid</AzureAdDeviceId>
    <Enabled>boolean</Enabled>
    <UserPrincipalName>string</UserPrincipalName>
    <MDM>string</MDM>
    <Activity>Active|Inactive</Activity>
    <LastCheckIn>ISO8601</LastCheckIn>
    <BitLocker>
      <Drive type="OperatingSystem">
        <BackedUp>ISO8601|true|false</BackedUp>
        <Encrypted>true|false</Encrypted>
      </Drive>
      <Drive type="Data">
        <BackedUp>ISO8601|true|false</BackedUp>
        <Encrypted>true|false</Encrypted>
      </Drive>
    </BitLocker>
    <LAPS>
      <Available>true|false</Available>
      <Retrieved>false</Retrieved>
    </LAPS>
  </Device>
  <!-- ... more devices ... -->
</WindowsAudit>
```

### CSV Columns (`WindowsAudit-*.csv`)

| Column | Type | Description |
|--------|------|-------------|
| `Name` | string | Device display name |
| `DeviceID` | guid | Directory object ID |
| `Enabled` | boolean | Account enabled status |
| `UserPrincipalName` | string | Primary user |
| `MDM` | string | "Microsoft Intune" or empty |
| `Activity` | string | "Active" or "Inactive" |
| `LastCheckIn` | ISO8601 | Last Intune sync time |
| `BitLockerOSBackedUp` | boolean | OS drive key backed up |
| `BitLockerDataBackedUp` | boolean | Data drive key backed up |
| `BitLockerOSEncrypted` | boolean | OS drive encrypted |
| `BitLockerDataEncrypted` | boolean | Data drive encrypted |
| `LAPSAvailable` | boolean | LAPS password exists |

---

## Security Notes

- **No secrets exposed**: BitLocker recovery keys and LAPS passwords are never retrieved or logged
- **Metadata only**: Only existence/backup status is recorded
- **Read-only operations**: Script cannot modify any devices or credentials
- **Audit logging**: All Graph calls logged with timestamps for audit trail
