## ADDED Requirements

### Requirement: Dedicated App Registration
The audit tooling SHALL support using a dedicated "Audit Windows" application registration instead of the shared Microsoft Graph PowerShell app, enabling tenant-specific Conditional Access policies, pre-consented permissions, and a clear audit trail.

#### Scenario: Admin provisions dedicated app registration
- **WHEN** an administrator runs `Setup-AuditWindowsApp.ps1` with Global Administrator or Application Administrator privileges
- **THEN** the script SHALL create an "Audit Windows" app registration in the target tenant
- **AND** configure exactly four application permissions: `Device.Read.All`, `BitLockerKey.ReadBasic.All`, `DeviceLocalCredential.ReadBasic.All`, `DeviceManagementManagedDevices.Read.All`
- **AND** grant admin consent for all four permissions
- **AND** add a certificate credential to the app registration
- **AND** output a JSON summary containing ApplicationId, TenantId, and CertificateThumbprint.

#### Scenario: Operator uses dedicated app for delegated auth
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppRegistration`
- **THEN** the script SHALL look up the "Audit Windows" app registration by display name
- **AND** connect to Microsoft Graph using the dedicated app's ClientId
- **AND** log the dedicated app's client ID in the audit log
- **AND** Microsoft Entra sign-in logs SHALL record the activity under the "Audit Windows" application.

#### Scenario: Operator uses dedicated app for app-only auth
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId <tid>`
- **THEN** the script SHALL use the "Audit Windows" app registration with certificate authentication
- **AND** the existing app-only flow SHALL continue to work unchanged.

#### Scenario: Default behavior preserved
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1` without `-UseAppRegistration`
- **THEN** the script SHALL use the default Microsoft Graph PowerShell app for delegated auth
- **AND** existing behavior SHALL be unchanged.

### Requirement: Pre-Consented Permissions
The dedicated app registration SHALL have all required Graph permissions pre-consented by an administrator, so operators do not need to self-consent at runtime.

#### Scenario: Permissions are pre-consented
- **WHEN** an operator connects using the dedicated "Audit Windows" app
- **THEN** no consent prompt SHALL appear
- **AND** the operator SHALL have access to all four required Graph endpoints.

### Requirement: Application Branding
The setup script SHALL upload a logo for the "Audit Windows" app registration if a `logo.jpg` file is present in the script's working directory.

#### Scenario: Logo uploaded when present
- **WHEN** an administrator runs `Setup-AuditWindowsApp.ps1`
- **AND** a file named `logo.jpg` exists in the same directory as the script
- **THEN** the script SHALL upload the logo to the app registration using `Set-MgApplicationLogo`
- **AND** log success or failure of the upload.

#### Scenario: Logo upload skipped when not present
- **WHEN** an administrator runs `Setup-AuditWindowsApp.ps1`
- **AND** no `logo.jpg` file exists in the script's directory
- **THEN** the script SHALL emit a warning that no logo was found
- **AND** continue with app provisioning without error.

### Requirement: Conditional Access Compatibility
The dedicated app registration SHALL appear as a distinct application in Microsoft Entra, enabling administrators to target it with Conditional Access policies.

#### Scenario: Conditional Access policy targets dedicated app
- **GIVEN** an administrator creates a Conditional Access policy targeting the "Audit Windows" application
- **WHEN** an operator attempts to authenticate using `-UseAppRegistration`
- **THEN** the Conditional Access policy SHALL be evaluated and enforced
- **AND** the policy SHALL NOT affect other Graph PowerShell usage in the tenant.
