## Why
The script currently requests `Directory.Read.All` at runtime even though `Device.Read.All` already covers the `/devices` endpoint. Similarly, provisioning requests `Directory.ReadWrite.All` when `Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All` suffice for app/SP/role-assignment creation. Removing these redundant scopes reduces blast radius and aligns with least-privilege IAM practices.

## What Changes
- Remove `Directory.Read.All` from delegated (interactive) scopes in `Get-EntraWindowsDevices.ps1`.
- Remove `Directory.Read.All` from app-only application permissions granted during provisioning.
- Remove `Directory.ReadWrite.All` from the admin provisioning scopes.
- Update documentation (README, ApplicationSpecification, project.md, ChangeRequestTemplate) to reflect the reduced permission set.

## Impact
- Affected specs: `security`
- Affected code: `Get-EntraWindowsDevices.ps1` (lines 216, 252, 310)
- Affected docs: `README.md`, `ApplicationSpecification.md`, `openspec/project.md`, `ChangeRequestTemplate.md`
- **Risk**: Provisioning may fail in tenants with stricter policies that require `Directory.ReadWrite.All`. Mitigation: document rollback steps and test in target environment before deploying.
