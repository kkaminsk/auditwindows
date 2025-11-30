# Get-AuditWindowsKeyVaultCertificate

Retrieves or creates a certificate from Azure Key Vault for Audit Windows app-only authentication.

## Synopsis

Provides centralized, HSM-backed (with Premium SKU) certificate storage with audit logging and easier rotation compared to local certificate storage.

## Syntax

```powershell
Get-AuditWindowsKeyVaultCertificate
    -VaultName <string>
    [-CertificateName <string>]
    [-CreateIfMissing]
    [-CreateVaultIfMissing]
    [-ResourceGroupName <string>]
    [-Location <string>]
    [-ValidityInMonths <int>]
    [-Subject <string>]
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-VaultName` | string | (required) | Name of the Azure Key Vault |
| `-CertificateName` | string | `'AuditWindowsCert'` | Name of the certificate in Key Vault |
| `-CreateIfMissing` | switch | — | Create the certificate if it doesn't exist |
| `-CreateVaultIfMissing` | switch | — | Create the Key Vault if it doesn't exist |
| `-ResourceGroupName` | string | — | Resource group for new vault (required with `-CreateVaultIfMissing`) |
| `-Location` | string | — | Azure region for new vault (required with `-CreateVaultIfMissing`) |
| `-ValidityInMonths` | int | `24` | Validity period for new certificates |
| `-Subject` | string | `'CN=AuditWindowsCert'` | Subject name for new certificates |

## Output

Returns a `PSCustomObject` with the following properties:

| Property | Type | Description |
|----------|------|-------------|
| `Certificate` | X509Certificate2 | The certificate object (or `$null` if failed) |
| `Thumbprint` | string | Certificate thumbprint |
| `KeyVaultUri` | string | URI of the certificate in Key Vault |
| `Success` | bool | Whether the operation succeeded |
| `Message` | string | Status or error message |

## Prerequisites

1. **Az.KeyVault module**: Install with `Install-Module -Name Az.KeyVault -Scope CurrentUser`
2. **Azure authentication**: Run `Connect-AzAccount` before using this function
3. **Key Vault permissions**: Your identity needs `Get` and `List` permissions on certificates and secrets

### For HSM-backed certificates

Create the Key Vault with Premium SKU:

```powershell
az keyvault create --name 'mykeyvault' --resource-group 'mygroup' --sku premium --location 'eastus'
```

## Examples

### Retrieve existing certificate

```powershell
$result = Get-AuditWindowsKeyVaultCertificate -VaultName 'mykeyvault'
if ($result.Success) {
    Write-Host "Certificate thumbprint: $($result.Thumbprint)"
} else {
    Write-Error $result.Message
}
```

### Create certificate if missing

```powershell
$result = Get-AuditWindowsKeyVaultCertificate -VaultName 'mykeyvault' -CreateIfMissing -ValidityInMonths 36
```

### Use custom certificate name

```powershell
$result = Get-AuditWindowsKeyVaultCertificate -VaultName 'mykeyvault' -CertificateName 'AuditWindowsProd'
```

### Create vault and certificate if missing

```powershell
$result = Get-AuditWindowsKeyVaultCertificate -VaultName 'mykeyvault' -CreateIfMissing -CreateVaultIfMissing -ResourceGroupName 'rg-audit' -Location 'eastus'
```

## Security Benefits

| Feature | Local Store | Key Vault |
|---------|-------------|-----------|
| Private key protection | Software-based | HSM-backed (Premium) |
| Access control | Windows ACLs | Azure RBAC + Access Policies |
| Audit logging | Windows Security Log | Azure Monitor / Log Analytics |
| Key rotation | Manual | Automatic policies available |
| Backup/recovery | Manual PFX export | Automatic vault backup |
| Multi-machine access | Copy PFX | Centralized retrieval |

## Related

- [Setup-AuditWindowsApp.ps1](../README.md#setup-auditwindowsappps1) - Setup script with Key Vault integration
- [Test-AuditWindowsCertificateHealth](./Test-AuditWindowsCertificateHealth.md) - Certificate expiration monitoring
- [Azure Key Vault documentation](https://docs.microsoft.com/azure/key-vault/)
