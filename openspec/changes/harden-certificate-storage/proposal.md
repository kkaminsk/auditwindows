## Why

Certificates for app-only authentication are currently stored in `Cert:\CurrentUser\My` with `KeyExportPolicy Exportable`, which allows any process running under the same user context to export private keys. This poses a credential theft risk on compromised or stolen workstations. The Security Audit (Section 3.1) recommends hardening certificate storage.

## What Changes

- Add `-NonExportable` switch to `Setup-AuditWindowsApp.ps1` for creating non-exportable certificates.
- Setup-AuditWindowsApp.ps1 when run in interactive mode will prompt to have the certificate set as exportable or not.
- Add `-UseKeyVault` parameter set for Azure Key Vault certificate storage
- Add new function `Test-AuditWindowsCertificateHealth` for certificate expiration monitoring (addresses Security Audit 3.3)
- Modify `Set-AuditWindowsKeyCredential` to support both exportable and non-exportable certificates
- Add new function `Get-AuditWindowsKeyVaultCertificate` for Key Vault integration
- Update documentation to recommend secure storage options

## Impact

- Affected specs: `security`
- Affected code:
  - `Setup-AuditWindowsApp.ps1` - Add new parameters
  - `functions/Set-AuditWindowsKeyCredential.ps1` - Support non-exportable option
  - `functions/Initialize-AppRegistrationAndConnect.ps1` - Support Key Vault certificates
  - New: `functions/Test-AuditWindowsCertificateHealth.ps1`
  - New: `functions/Get-AuditWindowsKeyVaultCertificate.ps1`
  - `README.md` - Document new options
