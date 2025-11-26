## Why
Interactive and app-only flows currently request the broad `BitLockerKey.Read.All` and `DeviceLocalCredential.Read.All` Graph scopes. Those permissions can reveal recovery keys and LAPS passwords, which exceeds the tool's need to only audit backup status. To align with least-privilege IAM practices, we should adopt the `ReadBasic` variants that expose only metadata.

## What Changes
- Replace delegated scopes `BitLockerKey.Read.All` and `DeviceLocalCredential.Read.All` with `BitLockerKey.ReadBasic.All` and `DeviceLocalCredential.ReadBasic.All` in `Get-EntraWindowsDevices.ps1`.
- Ensure app-only provisioning grants the reduced application roles.
- Update helper scripts (e.g., `Test-LAPS.ps1`, `Debug-LAPS.ps1`) so they authenticate with the reduced scopes.
- Refresh documentation (Application spec + OpenSpec project file) to state the new permission requirements.

## Impact
- Affected specs: `security`
- Affected code: `Get-EntraWindowsDevices.ps1`, `Test-LAPS.ps1`, `Debug-LAPS.ps1`
- Affected docs: `ApplicationSpecification.md`, `openspec/project.md`
