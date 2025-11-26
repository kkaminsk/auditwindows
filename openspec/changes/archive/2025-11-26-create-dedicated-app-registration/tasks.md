## 1. Create Module and Shared Helpers
- [x] 1.1 Create `modules/AuditWindows.Automation.psm1` with:
  - `Get-AuditWindowsPermissionNames` returning the 4 required permissions
  - `Get-AuditWindowsGraphResourceAccess` to build RequiredResourceAccess structure
  - Certificate helper functions (thumbprint normalization, key credential lookup)
  - `New-AuditWindowsSummaryRecord` for JSON output

## 2. Create Setup Functions
- [x] 2.1 Create `functions/Connect-AuditWindowsGraph.ps1` — admin auth with `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`
- [x] 2.2 Create `functions/Set-AuditWindowsApplication.ps1` — create/update app registration
- [x] 2.3 Create `functions/Set-AuditWindowsPermissions.ps1` — configure RequiredResourceAccess
- [x] 2.4 Create `functions/Grant-AuditWindowsConsent.ps1` — grant admin consent via appRoleAssignment
- [x] 2.5 Create `functions/Set-AuditWindowsKeyCredential.ps1` — add certificate to app
- [x] 2.6 Create `functions/Write-AuditWindowsSummary.ps1` — output JSON summary

## 3. Create Setup Script
- [x] 3.1 Create `functions/Set-AuditWindowsLogo.ps1` — upload logo.jpg to app registration if present
- [x] 3.2 Create `Setup-AuditWindowsApp.ps1` with parameters:
  - `-AppDisplayName` (default: "Audit Windows")
  - `-CertificateSubject` (default: "CN=AuditWindowsCert")
  - `-CertificateValidityInMonths` (default: 24)
  - `-ExistingCertificateThumbprint` (optional: use existing cert)
  - `-TenantId` (optional: target specific tenant)
  - `-Force` (skip confirmation prompts)
- [x] 3.3 Implement main workflow: connect → create app → upload logo → set permissions → grant consent → add cert → output summary

## 4. Modify Main Script
- [x] 4.1 Add `-UseAppRegistration` switch parameter to `Get-EntraWindowsDevices.ps1`
- [x] 4.2 When `-UseAppRegistration` is set:
  - Look up "Audit Windows" app by display name
  - Use its AppId as `-ClientId` for `Connect-MgGraph`
  - Log the dedicated app's client ID
- [x] 4.3 Ensure existing `-UseAppAuth` behavior unchanged

## 5. Update Documentation
- [x] 5.1 Update `README.md`:
  - Add "Setup" section with `Setup-AuditWindowsApp.ps1` instructions
  - Document `-UseAppRegistration` parameter
  - Add Conditional Access example
- [x] 5.2 Update `ApplicationSpecification.md` with dedicated app architecture
- [x] 5.3 Update `ChangeRequestTemplate.md` with setup prerequisites

## 6. Validation
- [ ] 6.1 Run `Setup-AuditWindowsApp.ps1` in test tenant; verify app created with correct permissions
- [ ] 6.2 Run `Get-EntraWindowsDevices.ps1 -UseAppRegistration -MaxDevices 5`; verify sign-in logged under "Audit Windows" app
- [ ] 6.3 Verify app-only auth (`-UseAppAuth`) still works with existing provisioning flow
- [ ] 6.4 Review sign-in logs in Entra to confirm audit trail separation
