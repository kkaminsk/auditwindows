## 1. Non-Exportable Certificate Support

- [x] 1.1 Add `-NonExportable` switch parameter to `Setup-AuditWindowsApp.ps1`
- [x] 1.2 Modify `Set-AuditWindowsKeyCredential` to accept `-NonExportable` parameter
- [x] 1.3 Update `New-SelfSignedCertificate` call to use `KeyExportPolicy NonExportable` when flag is set
- [x] 1.4 Skip PFX export prompts when `-NonExportable` is specified (export not possible)
- [x] 1.5 Update `Initialize-AppRegistrationAndConnect.ps1` to support non-exportable certificates
- [x] 1.6 Add inline documentation for the trade-offs of non-exportable certificates

## 2. Certificate Health Check Function

- [x] 2.1 Create `functions/Test-AuditWindowsCertificateHealth.ps1` with parameters:
  - `-CertificateSubject` (default: 'CN=AuditWindowsCert')
  - `-CertificateThumbprint` (optional, takes precedence)
  - `-WarningDaysBeforeExpiry` (default: 30)
- [x] 2.2 Return structured object: `@{ Healthy = $bool; DaysUntilExpiry = $int; Certificate = $cert; Message = $string }`
- [x] 2.3 Create companion documentation `functions/Test-AuditWindowsCertificateHealth.md`
- [x] 2.4 Integrate health check into `Get-EntraWindowsDevices.ps1` with warning output
- [x] 2.5 Add `-SkipCertificateHealthCheck` parameter to suppress health check

## 3. Azure Key Vault Integration

- [x] 3.1 Create `functions/Get-AuditWindowsKeyVaultCertificate.ps1` with parameters:
  - `-VaultName` (required)
  - `-CertificateName` (default: 'AuditWindowsCert')
  - `-CreateIfMissing` (switch)
  - `-ValidityInMonths` (default: 24, used with CreateIfMissing)
- [x] 3.2 Implement Key Vault certificate retrieval using `Az.KeyVault` module
- [x] 3.3 Implement Key Vault certificate creation when `-CreateIfMissing` specified
- [x] 3.4 Create companion documentation `functions/Get-AuditWindowsKeyVaultCertificate.md`
- [x] 3.5 Add `-UseKeyVault`, `-VaultName`, `-KeyVaultCertificateName` parameters to `Setup-AuditWindowsApp.ps1`
- [x] 3.6 Add `-UseKeyVault`, `-VaultName`, `-KeyVaultCertificateName` parameters to `Get-EntraWindowsDevices.ps1`
- [x] 3.7 Modify `Initialize-AppRegistrationAndConnect.ps1` to support Key Vault certificate authentication
- [x] 3.8 Handle `Az.KeyVault` module import gracefully (install prompt or error message)

## 4. Documentation Updates

- [x] 4.1 Update `README.md` with new certificate storage options section
- [x] 4.2 Document security trade-offs: exportable vs non-exportable vs Key Vault
- [x] 4.3 Add examples for each certificate storage method
- [x] 4.4 Document certificate expiration monitoring and alerting recommendations

## 5. Validation

- [ ] 5.1 Test non-exportable certificate creation and authentication
- [ ] 5.2 Test certificate health check with valid, expiring, and expired certificates
- [ ] 5.3 Test Key Vault integration (certificate retrieval and creation)
- [ ] 5.4 Verify backward compatibility with existing exportable certificates
- [ ] 5.5 Verify error handling when Key Vault is unavailable
