# Get-EntraWindowsDevices.ps1 Execution Flow

This document describes the step-by-step execution flow of the `Get-EntraWindowsDevices.ps1` script.

---

## Overview

The script queries Windows devices from Entra ID (Azure AD), enriches them with Intune, BitLocker, and LAPS data, and generates XML/CSV audit reports.

---

## Execution Phases

### Phase 1: Initialization

| Step | Action | Details |
|------|--------|---------|
| 1.1 | **Capture Start Time** | `$start = Get-Date` for duration tracking |
| 1.2 | **Generate Timestamp** | Format: `yyyy-MM-dd-HH-mm` for file naming |
| 1.3 | **Set Output Directory** | Uses `-OutputPath` or defaults to `[Environment]::GetFolderPath('MyDocuments')` |
| 1.4 | **Create Output Directory** | Creates directory if it doesn't exist |
| 1.5 | **Initialize File Paths** | Sets paths for log, XML, and CSV files |
| 1.6 | **Load Functions** | Dot-sources all `.ps1` files from `functions/` folder |
| 1.7 | **Log Script Start** | First log entry with output path |

**Output Files Initialized:**
- `WindowsAudit-{timestamp}.log`
- `WindowsAudit-{timestamp}.xml`
- `WindowsAudit-{timestamp}.csv` (if `-ExportCSV`)

### Phase 2: Module Import

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 2.1 | **Check Skip Flag** | Main script | If `-SkipModuleImport`, skip to Phase 3 |
| 2.2 | **Check Existing Commands** | `Import-GraphModuleIfNeeded` | Checks if all required Graph commands already available |
| 2.3 | **Install Missing Modules** | `Import-GraphModuleIfNeeded` | Installs to `CurrentUser` scope if not found |
| 2.4 | **Import Modules** | `Import-GraphModuleIfNeeded` | Loads modules with assembly conflict handling |

**Modules Imported:**
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Identity.DirectoryManagement`
- `Microsoft.Graph.DeviceManagement`
- `Microsoft.Graph.Applications` (only if `-UseAppAuth` or `-CreateAppIfMissing`)
- `Microsoft.Graph.ServicePrincipals` (only if `-UseAppAuth` or `-CreateAppIfMissing`)

### Phase 3: Authentication

The script supports two authentication modes:

#### Mode A: Delegated (Interactive) Authentication

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 3A.1 | **Lookup Dedicated App** | `Connect-GraphInteractive` | Connects with `Application.Read.All` to find app by name |
| 3A.2 | **Validate App Exists** | `Connect-GraphInteractive` | Throws error if app not found (prompts to run Setup-AuditWindowsApp.ps1) |
| 3A.3 | **Connect with App** | `Connect-GraphInteractive` | Connects using app's ClientId with delegated scopes |
| 3A.4 | **Device Code Flow** | `Connect-GraphInteractive` | Uses device code if `-UseDeviceCode` specified |

**Delegated Scopes Requested:**
- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

#### Mode B: App-Only (Certificate) Authentication

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 3B.1 | **Validate TenantId** | Main script | Throws if `-TenantId` not provided |
| 3B.2 | **Provisioning Mode** | `Initialize-AppRegistrationAndConnect` | If `-CreateAppIfMissing`: |
| | | | - Connect with admin scopes (device code) |
| | | | - Create/find application registration |
| | | | - Create/find service principal |
| | | | - Create/find self-signed certificate |
| | | | - Add certificate to app keyCredentials |
| | | | - Grant application permissions |
| 3B.3 | **Non-Provisioning Mode** | `Initialize-AppRegistrationAndConnect` | If no `-CreateAppIfMissing`: |
| | | | - Find existing certificate by subject |
| | | | - Look up existing application |
| 3B.4 | **Connect App-Only** | `Initialize-AppRegistrationAndConnect` | `Connect-MgGraph -CertificateThumbprint` |

**Application Permissions (App-Only):**
- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

### Phase 4: Device Query

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 4.1 | **Log Auth Context** | Main script | Records AuthType, TenantId, ClientId, Account |
| 4.2 | **Query Windows Devices** | `Get-WindowsDirectoryDevices` | Filters: `operatingSystem eq 'Windows'` |
| 4.3 | **Filter by Name** | Main script | If `-DeviceName` specified, filters to matching device |
| 4.4 | **Limit Results** | Main script | If `-MaxDevices` specified, takes first N devices |
| 4.5 | **Initialize XML** | `New-AuditXml` | Creates `<WindowsAudit>` root document |
| 4.6 | **Initialize Summary** | Main script | Empty array for CSV summary records |

**Graph API Call:**
```
GET /devices?$select=id,displayName,deviceId,accountEnabled,operatingSystem&$filter=operatingSystem eq 'Windows'
```

### Phase 5: Device Processing Loop

For each device, the following steps are executed:

| Step | Action | Function | Details |
|------|--------|----------|---------|
| 5.1 | **Update Progress** | Main script | `Write-Progress` with percentage |
| 5.2 | **Resolve Device IDs** | Main script | Extracts `ObjectId` and `AzureAdDeviceId` |
| 5.3 | **Get Intune Data** | `Get-ManagedDeviceByAadId` | Queries Intune for UPN, LastSyncDateTime |
| 5.4 | **Get BitLocker Keys** | `Get-BitLockerKeysByDeviceId` | Queries BitLocker recovery key metadata |
| 5.5 | **Fallback BitLocker** | Main script | If no keys found with AzureAdDeviceId, tries ObjectId |
| 5.6 | **Check LAPS** | `Test-LapsAvailable` | Queries LAPS credential availability |
| 5.7 | **Parse BitLocker** | Main script | Classifies keys by volume type (OS/Data) |
| 5.8 | **Build XML Node** | Main script | Creates `<Device>` element with all data |
| 5.9 | **Build Summary Record** | Main script | Creates PSCustomObject for CSV |
| 5.10 | **Log Export** | Main script | Outputs "{DeviceName} exported" |

#### 5.3 Intune Lookup Details

| Function | API Call |
|----------|----------|
| `Get-ManagedDeviceByAadId` | `GET /deviceManagement/managedDevices?$filter=azureADDeviceId eq '{id}'` |

**Data Retrieved:**
- `UserPrincipalName`
- `LastSyncDateTime`

**Activity Calculation:**
- **Active**: LastSyncDateTime within 30 days
- **Inactive**: LastSyncDateTime older than 30 days
- **null**: No Intune enrollment

#### 5.4 BitLocker Lookup Details

| Function | API Call |
|----------|----------|
| `Get-BitLockerKeysByDeviceId` | `GET /informationProtection/bitlocker/recoveryKeys?$filter=deviceId eq '{id}'` |

**Data Retrieved:**
- `VolumeType` (OperatingSystemVolume, FixedDataVolume)
- `CreatedDateTime`

**Volume Type Normalization:**
- OS Drive: `operatingsystemvolume`, `operatingsystemdrive`, `os`, `1`, or null
- Data Drive: `fixeddatavolume`, `fixeddatadrive`, `data`, `2`

#### 5.6 LAPS Lookup Details

| Function | API Call |
|----------|----------|
| `Test-LapsAvailable` | `GET /directory/deviceLocalCredentials?$filter=deviceName eq '{name}'` |

**Returns:** `$true` if credentials exist, `$false` otherwise

### Phase 6: Output Generation

| Step | Action | Details |
|------|--------|---------|
| 6.1 | **Save XML** | `$xml.Save($xmlPath)` |
| 6.2 | **Log XML Path** | Records path to log file |
| 6.3 | **Export CSV** | If `-ExportCSV`, calls `Export-Csv` |
| 6.4 | **Log CSV Path** | Records path to log file (if exported) |
| 6.5 | **Calculate Duration** | `(Get-Date) - $start` in seconds |
| 6.6 | **Log Completion** | Final log entry with duration |

---

## Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        INITIALIZATION                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Start Timer  │→ │ Set Paths    │→ │ Create Dirs  │→ │ Load Funcs   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        MODULE IMPORT                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Import-GraphModuleIfNeeded                                        │   │
│  │  → Check if commands exist (skip if -SkipModuleImport)            │   │
│  │  → Install missing modules to CurrentUser                         │   │
│  │  → Import with assembly conflict handling                         │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        AUTHENTICATION                                    │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐   │
│  │ -UseAppAuth = $false        │  │ -UseAppAuth = $true             │   │
│  │ ─────────────────────────── │  │ ─────────────────────────────── │   │
│  │ Connect-GraphInteractive    │  │ Initialize-AppRegistrationAnd   │   │
│  │  → Lookup dedicated app     │  │ Connect                         │   │
│  │  → Connect with ClientId    │  │  → Provision app (if -Create)   │   │
│  │  → Delegated scopes         │  │  → Connect with certificate     │   │
│  │  → Device code optional     │  │  → App-only permissions         │   │
│  └─────────────────────────────┘  └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEVICE QUERY                                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Get-WindowsDirectoryDevices                                       │   │
│  │  → GET /devices?$filter=operatingSystem eq 'Windows'              │   │
│  │  → Filter by -DeviceName (optional)                               │   │
│  │  → Limit by -MaxDevices (optional)                                │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                     DEVICE PROCESSING LOOP                               │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ For each device:                                                  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │ 1. Get-ManagedDeviceByAadId → Intune UPN, LastSync         │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │ 2. Get-BitLockerKeysByDeviceId → Recovery key metadata     │  │   │
│  │  │    (fallback to ObjectId if AzureAdDeviceId returns empty) │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │ 3. Test-LapsAvailable → LAPS credential availability       │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │ 4. Parse BitLocker keys by volume type (OS/Data)           │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │ 5. Build XML <Device> node with all data                   │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │ 6. Build CSV summary record                                 │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                       OUTPUT GENERATION                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Save XML     │→ │ Export CSV   │→ │ Log Duration │→ │ Complete     │ │
│  │              │  │ (if flag)    │  │              │  │              │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## XML Output Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<WindowsAudit>
  <Device>
    <Name>DESKTOP-ABC123</Name>
    <DeviceID>{object-id}</DeviceID>
    <AzureAdDeviceId>{device-id}</AzureAdDeviceId>
    <Enabled>True</Enabled>
    <UserPrincipalName>user@contoso.com</UserPrincipalName>
    <MDM>Microsoft Intune</MDM>
    <Activity>Active</Activity>
    <LastCheckIn>2025-11-15T10:30:00.0000000Z</LastCheckIn>
    <BitLocker>
      <Drive type="OperatingSystem">
        <BackedUp>2025-01-15T08:00:00.0000000Z</BackedUp>
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
  <!-- ... more devices ... -->
</WindowsAudit>
```

---

## CSV Output Columns

| Column | Source | Description |
|--------|--------|-------------|
| `Name` | Entra ID | Device display name |
| `DeviceID` | Entra ID | Directory object ID |
| `Enabled` | Entra ID | Account enabled status |
| `UserPrincipalName` | Intune | Primary user UPN |
| `MDM` | Intune | "Microsoft Intune" if enrolled |
| `Activity` | Calculated | Active/Inactive (30-day threshold) |
| `LastCheckIn` | Intune | Last sync timestamp (ISO 8601) |
| `BitLockerOSBackedUp` | Graph | OS drive key backed up |
| `BitLockerDataBackedUp` | Graph | Data drive key backed up |
| `BitLockerOSEncrypted` | Calculated | OS drive encrypted |
| `BitLockerDataEncrypted` | Calculated | Data drive encrypted |
| `LAPSAvailable` | Graph | LAPS password exists |

---

## Retry Logic

The `Invoke-GraphWithRetry` function handles transient failures:

| Status Code | Action | Wait Strategy |
|-------------|--------|---------------|
| 429 | Retry | Respects `Retry-After` header |
| 502, 503, 504 | Retry | Exponential backoff (max 60s) |
| 404 | Non-fatal | Returns empty (BitLocker/LAPS) |
| Other errors | Fail | After max 4 retries |

**Retry Formula:** `wait = min(2 * 2^attempt, 60)` seconds

---

## Error Handling

| Phase | Error Condition | Action |
|-------|-----------------|--------|
| Auth | App not found | Throws with guidance to run Setup-AuditWindowsApp.ps1 |
| Auth | Certificate not found | Throws with `-CertSubject` hint |
| Auth | TenantId missing (app-only) | Throws immediately |
| Device Loop | Intune lookup fails | Logs WARN, continues (fields null) |
| Device Loop | BitLocker lookup fails | Logs WARN, tries fallback ID, continues |
| Device Loop | LAPS lookup fails | Logs WARN, continues (Available=false) |

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `OutputPath` | string | `My Documents` | Directory for output files |
| `ExportCSV` | switch | `$false` | Generate CSV in addition to XML |
| `UseDeviceCode` | switch | `$false` | Use device code flow for interactive auth |
| `MaxDevices` | int | — | Limit number of devices processed |
| `UseAppAuth` | switch | `$false` | Use certificate-based app-only auth |
| `CreateAppIfMissing` | switch | `$false` | Provision app registration if not found |
| `AppName` | string | `'WindowsAuditApp'` | App name for provisioning (legacy) |
| `AppDisplayName` | string | `'Audit Windows'` | App display name for lookup |
| `TenantId` | string | — | Required for `-UseAppAuth` |
| `CertSubject` | string | `'CN={AppName}'` | Certificate subject for app-only auth |
| `SkipModuleImport` | switch | `$false` | Skip Graph module installation/import |
| `DeviceName` | string | — | Filter to single device by name |

---

## REST Fallback

When Graph cmdlets are unavailable, the script falls back to direct REST calls:

| Function | Cmdlet | REST Fallback |
|----------|--------|---------------|
| `Get-WindowsDirectoryDevices` | `Get-MgDevice` | `Invoke-GraphGetAll /devices?$filter=...` |
| `Get-ManagedDeviceByAadId` | `Get-MgDeviceManagementManagedDevice` | `Invoke-GraphGetAll /deviceManagement/managedDevices?$filter=...` |
| `Get-BitLockerKeysByDeviceId` | `Get-MgInformationProtectionBitlockerRecoveryKey` | `Invoke-GraphGetAll /informationProtection/bitlocker/recoveryKeys?$filter=...` |
| `Test-LapsAvailable` | — | `Invoke-GraphGet /directory/deviceLocalCredentials?$filter=...` |

The `Invoke-GraphGetAll` function handles OData pagination via `@odata.nextLink`.
