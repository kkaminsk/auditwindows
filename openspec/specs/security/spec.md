# security Specification

## Purpose
TBD - created by archiving change create-dedicated-app-registration. Update Purpose after archive.
## Requirements
### Requirement: Dedicated App Registration
The audit tooling SHALL support using a dedicated "Audit Windows" application registration instead of the shared Microsoft Graph PowerShell app, enabling tenant-specific Conditional Access policies, pre-consented permissions, and a clear audit trail.

#### Scenario: Admin provisions dedicated app registration
- **WHEN** an administrator runs `Setup-AuditWindowsApp.ps1` with Global Administrator or Application Administrator privileges
- **THEN** the script SHALL create an "Audit Windows" app registration in the target tenant
- **AND** configure exactly four application permissions: `Device.Read.All`, `BitLockerKey.ReadBasic.All`, `DeviceLocalCredential.ReadBasic.All`, `DeviceManagementManagedDevices.Read.All`
- **AND** grant admin consent for all four permissions
- **AND** add a certificate credential to the app registration (unless `-SkipCertificate` is specified)
- **AND** output a JSON summary containing ApplicationId, TenantId, and CertificateThumbprint (if applicable).

#### Scenario: Operator uses dedicated app for delegated auth
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppRegistration`
- **THEN** the script SHALL look up the "Audit Windows" app registration by display name
- **AND** connect to Microsoft Graph using the dedicated app's ClientId
- **AND** log the dedicated app's client ID in the audit log
- **AND** Microsoft Entra sign-in logs SHALL record the activity under the "Audit Windows" application.

#### Scenario: Operator uses dedicated app for app-only auth
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId <tid>`
- **THEN** the script SHALL use the "Audit Windows" app registration with certificate authentication
- **AND** the script SHALL perform a certificate health check unless `-SkipCertificateHealthCheck` is specified
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

### Requirement: Non-Exportable Certificate Option
The setup tooling SHALL support creating certificates with non-exportable private keys to prevent credential theft from compromised workstations.

#### Scenario: Administrator creates non-exportable certificate
- **WHEN** an administrator runs `Setup-AuditWindowsApp.ps1 -NonExportable`
- **THEN** the script SHALL create a self-signed certificate with `KeyExportPolicy NonExportable`
- **AND** the certificate SHALL be stored in `Cert:\CurrentUser\My`
- **AND** the script SHALL NOT prompt for PFX export (export is not possible)
- **AND** the script SHALL display a warning that the certificate cannot be backed up or migrated.

#### Scenario: Non-exportable certificate used for authentication
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppAuth` with a non-exportable certificate
- **THEN** authentication SHALL succeed using the certificate from the local store
- **AND** the private key SHALL remain protected from export.

### Requirement: Azure Key Vault Certificate Storage
The tooling SHALL support storing and retrieving authentication certificates from Azure Key Vault for centralized, HSM-backed credential management.

#### Scenario: Administrator configures Key Vault certificate storage
- **WHEN** an administrator runs `Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'MyVault'`
- **THEN** the script SHALL retrieve or create a certificate in the specified Azure Key Vault
- **AND** the script SHALL attach the certificate's public key to the app registration
- **AND** the script SHALL NOT store the private key locally.

#### Scenario: Key Vault certificate retrieval at runtime
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppAuth -UseKeyVault -VaultName 'MyVault'`
- **THEN** the script SHALL retrieve the certificate from Azure Key Vault
- **AND** the script SHALL authenticate to Microsoft Graph using the Key Vault-backed certificate
- **AND** private key operations SHALL be performed via Key Vault API.

#### Scenario: Key Vault certificate creation when missing
- **WHEN** an administrator runs `Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'MyVault' -CreateIfMissing`
- **AND** no certificate named 'AuditWindowsCert' exists in the vault
- **THEN** the script SHALL create a new certificate in Azure Key Vault
- **AND** the certificate SHALL have a validity period of 24 months by default.

#### Scenario: Key Vault unavailable
- **WHEN** an operator runs the audit script with `-UseKeyVault`
- **AND** the Azure Key Vault is unreachable or the operator lacks permissions
- **THEN** the script SHALL fail with a clear error message indicating the Key Vault access issue
- **AND** the script SHALL NOT fall back to local certificate storage without explicit configuration.

### Requirement: Certificate Health Monitoring
The tooling SHALL provide certificate expiration monitoring to prevent silent authentication failures.

#### Scenario: Certificate health check at runtime
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppAuth`
- **THEN** the script SHALL check the certificate expiration date before processing devices
- **AND** if the certificate expires within 30 days, the script SHALL display a warning message
- **AND** the script SHALL continue execution (non-blocking warning).

#### Scenario: Certificate health check suppressed
- **WHEN** an operator runs `Get-EntraWindowsDevices.ps1 -UseAppAuth -SkipCertificateHealthCheck`
- **THEN** the script SHALL NOT perform the certificate expiration check.

#### Scenario: Dedicated health check function
- **WHEN** an operator calls `Test-AuditWindowsCertificateHealth -CertificateThumbprint 'ABC123'`
- **THEN** the function SHALL return a structured object containing:
  - `Healthy`: Boolean indicating if certificate is valid and not expiring soon
  - `DaysUntilExpiry`: Integer days until certificate expires
  - `Certificate`: The certificate object
  - `Message`: Human-readable status message
- **AND** the function SHALL support a configurable warning threshold via `-WarningDaysBeforeExpiry`.

#### Scenario: Health check for Key Vault certificate
- **WHEN** an operator calls `Test-AuditWindowsCertificateHealth -UseKeyVault -VaultName 'MyVault'`
- **THEN** the function SHALL retrieve the certificate from Azure Key Vault
- **AND** the function SHALL check the Key Vault certificate's expiration date
- **AND** the function SHALL return the same structured health object.

