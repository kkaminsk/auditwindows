## Why
Currently, delegated auth uses Microsoft's shared `Microsoft Graph PowerShell` app (`14d82eec-204b-4c2f-b7e8-296a70dab67e`), which:
- Mixes audit tool activity with other Graph PowerShell usage in sign-in logs
- Cannot be targeted by Conditional Access policies
- Cannot have permissions pre-consented at the app level
- Cannot be revoked independently of other Graph PowerShell usage

A dedicated "Audit Windows" app registration provides:
- Clear audit trail in Entra sign-in logs
- Conditional Access targeting (require MFA, restrict locations/users)
- Pre-consented permissions with admin approval
- Independent lifecycle management
- Support for both delegated and app-only (certificate) auth

## What Changes
1. Create a new `Setup-AuditWindowsApp.ps1` script (modeled after `refscripts/Setup-PortalFuseApp.ps1`) that:
   - Creates/updates an "Audit Windows" app registration in the target tenant
   - Configures exactly the 4 required Graph application permissions
   - Grants admin consent automatically
   - Generates or imports a certificate credential
   - Outputs a JSON summary for operational records

2. Create supporting infrastructure:
   - `modules/AuditWindows.Automation.psm1` — shared helpers (permission list, certificate utilities)
   - `functions/` folder with reusable functions (connect, set permissions, grant consent)

3. Modify `Get-EntraWindowsDevices.ps1` to:
   - Add `-UseAppRegistration` parameter to use the dedicated app for delegated auth
   - Look up the "Audit Windows" app's client ID from Entra and use it for `Connect-MgGraph`
   - Fall back to default Microsoft Graph PowerShell if the dedicated app isn't found

4. Update documentation (`README.md`, `ApplicationSpecification.md`, `ChangeRequestTemplate.md`) with:
   - Instructions for running `Setup-AuditWindowsApp.ps1`
   - New parameter documentation
   - Updated permission guidance

## Impact
- Affected specs: `security`
- New files: `Setup-AuditWindowsApp.ps1`, `modules/AuditWindows.Automation.psm1`, `functions/*.ps1`
- Modified files: `Get-EntraWindowsDevices.ps1`, `README.md`, `ApplicationSpecification.md`, `ChangeRequestTemplate.md`
- **Risk**: Low — existing behavior preserved by default; new parameter opts in to dedicated app
