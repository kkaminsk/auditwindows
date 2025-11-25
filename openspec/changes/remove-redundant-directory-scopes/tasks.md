## 1. Implementation
- [x] 1.1 Remove `Directory.Read.All` from delegated scopes in `Connect-GraphInteractive` (line 216).
- [x] 1.2 Remove `Directory.Read.All` from app-only `$needed` permissions array (line 310).
- [x] 1.3 Remove `Directory.ReadWrite.All` from admin provisioning `$adminScopes` (line 252).
- [x] 1.4 Update `README.md` permissions sections to remove `Directory.Read.All` from runtime and `Directory.ReadWrite.All` from provisioning.
- [x] 1.5 Update `ApplicationSpecification.md` to reflect the reduced permission set.
- [x] 1.6 Update `openspec/project.md` constraints to list only the four required runtime scopes.
- [x] 1.7 Update `ChangeRequestTemplate.md` to remove `Directory.Read.All` from runtime permissions table.

## 2. Validation
- [ ] 2.1 Run script with delegated auth (`-MaxDevices 5`) and confirm devices, BitLocker, LAPS data retrieved.
- [ ] 2.2 Run provisioning flow (`-UseAppAuth -CreateAppIfMissing`) in a test tenant and confirm app/SP/cert/roles created successfully.
- [ ] 2.3 Verify XML output matches expected schema.
- [ ] 2.4 Document any tenant-specific failures and rollback steps.
