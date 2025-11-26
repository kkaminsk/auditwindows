## ADDED Requirements
### Requirement: Least-Privilege Graph Permissions
The audit tooling SHALL use only `ReadBasic` Microsoft Graph scopes for BitLocker keys and device local credentials so that recovery secrets cannot be retrieved by the application.

#### Scenario: Delegated authentication honors least privilege
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1` interactively (with or without device code)
- **THEN** the script SHALL request `BitLockerKey.ReadBasic.All` and `DeviceLocalCredential.ReadBasic.All` (instead of the broader `Read.All` scopes)
- **AND** the script SHALL still gather BitLocker/LAPS metadata successfully.

#### Scenario: App-only provisioning honors least privilege
- **WHEN** the script provisions or validates an app registration for app-only auth
- **THEN** it SHALL ensure the service principal is granted the `BitLockerKey.ReadBasic.All` and `DeviceLocalCredential.ReadBasic.All` application roles
- **AND** no broader permission is requested unless explicitly approved by future specs.
