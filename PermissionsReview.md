# Entra ID Permission Review

## Observed Application Permissions
- **Delegated authentication** requests Microsoft Graph scopes `Device.Read.All`, `BitLockerKey.ReadBasic.All`, `Directory.Read.All`, `DeviceLocalCredential.ReadBasic.All`, and `DeviceManagementManagedDevices.Read.All` when connecting interactively. 【F:Get-EntraWindowsDevices.ps1†L215-L233】
- **App-only authentication** provisions/assigns the same five application permissions on the Microsoft Graph service principal. 【F:Get-EntraWindowsDevices.ps1†L308-L323】
- **App provisioning flow** uses elevated delegated scopes `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`, and `Directory.ReadWrite.All` to create the app registration, service principal, certificate credentials, and role assignments. 【F:Get-EntraWindowsDevices.ps1†L248-L326】

## Permissions Needed by Features
- **Windows device inventory (`/devices`)** – requires `Device.Read.All` (or `Directory.Read.All`). 【F:Get-EntraWindowsDevices.ps1†L344-L344】
- **Intune managed device metadata (`/deviceManagement/managedDevices`)** – requires `DeviceManagementManagedDevices.Read.All`. 【F:Get-EntraWindowsDevices.ps1†L345-L345】
- **BitLocker recovery key metadata (`/informationProtection/bitlocker/recoveryKeys`)** – requires `BitLockerKey.ReadBasic.All` to read non-secret key metadata. 【F:Get-EntraWindowsDevices.ps1†L346-L346】
- **LAPS availability check (`/directory/deviceLocalCredentials`)** – requires `DeviceLocalCredential.ReadBasic.All` when only checking for existence (no secrets retrieved). 【F:Get-EntraWindowsDevices.ps1†L347-L347】

## Gaps and Findings
- **Extra directory read scope in normal operation** – `Directory.Read.All` is requested alongside `Device.Read.All` even though device reads are already covered by `Device.Read.All`. Removing `Directory.Read.All` from the interactive scopes and assigned app roles would better align with least privilege unless other directory objects are queried later. 【F:Get-EntraWindowsDevices.ps1†L215-L233】【F:Get-EntraWindowsDevices.ps1†L308-L323】
- **Broad admin scopes during provisioning** – provisioning uses `Directory.ReadWrite.All` in addition to `Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All`. Creating an app registration, service principal, certificate credential, and role assignments can typically be done with the latter two scopes alone; dropping `Directory.ReadWrite.All` would reduce blast radius if not required by your tenant policies. 【F:Get-EntraWindowsDevices.ps1†L248-L326】
- **No missing permissions identified** – every Graph call in the script maps to a corresponding delegated/app permission, so runtime functionality should work once the above over-provisioned scopes are trimmed.

## Recommendations
1. Remove `Directory.Read.All` from the interactive and app-only permission sets unless future directory object reads are planned.
2. Audit whether `Directory.ReadWrite.All` is truly required for provisioning; if not, limit admin consent to `Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All`.
3. Keep the existing five app permissions (`Device.Read.All`, `BitLockerKey.ReadBasic.All`, `DeviceLocalCredential.ReadBasic.All`, `DeviceManagementManagedDevices.Read.All`) because they align with the script’s Graph usage.
