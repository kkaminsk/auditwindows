## MODIFIED Requirements
### Requirement: Least-Privilege Graph Permissions
The audit tooling SHALL use only the minimum Microsoft Graph scopes required for each operation:
- **Runtime (delegated/app-only)**: `Device.Read.All`, `BitLockerKey.ReadBasic.All`, `DeviceLocalCredential.ReadBasic.All`, `DeviceManagementManagedDevices.Read.All`
- **Provisioning (admin)**: `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`

The tooling SHALL NOT request `Directory.Read.All` or `Directory.ReadWrite.All` unless explicitly required by a future capability.

#### Scenario: Delegated authentication honors least privilege
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1` interactively (with or without device code)
- **THEN** the script SHALL request only `Device.Read.All`, `BitLockerKey.ReadBasic.All`, `DeviceLocalCredential.ReadBasic.All`, and `DeviceManagementManagedDevices.Read.All`
- **AND** the script SHALL NOT request `Directory.Read.All`
- **AND** the script SHALL still gather device, BitLocker, and LAPS metadata successfully.

#### Scenario: App-only provisioning honors least privilege
- **WHEN** the script provisions or validates an app registration for app-only auth
- **THEN** it SHALL request admin scopes `Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All` only
- **AND** it SHALL NOT request `Directory.ReadWrite.All`
- **AND** it SHALL grant only `Device.Read.All`, `BitLockerKey.ReadBasic.All`, `DeviceLocalCredential.ReadBasic.All`, and `DeviceManagementManagedDevices.Read.All` as application roles.

#### Scenario: Runtime app-only authentication honors least privilege
- **WHEN** the script connects with app-only (certificate) authentication
- **THEN** the service principal SHALL have only the four required application permissions
- **AND** `Directory.Read.All` SHALL NOT be assigned.
