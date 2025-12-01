# Set-AuditWindowsKeyCredential

Adds a certificate credential to the application.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Application` | object | Yes | - | Application object |
| `CertificateSubject` | string | No | `CN=AuditWindowsCert` | Certificate subject |
| `CertificateValidityInMonths` | int | No | 24 | Validity period (1-60 months) |
| `ExistingCertificateThumbprint` | string | No | - | Use existing cert by thumbprint |
| `SkipExport` | switch | No | - | Skip exporting certificate to files |
| `NonExportable` | switch | No | - | Create certificate with non-exportable private key |

## Returns

Certificate object from `Cert:\CurrentUser\My`.

## Behavior

- Uses existing cert if thumbprint provided
- Otherwise generates self-signed certificate (2048-bit RSA, SHA256)
- With `-NonExportable`: private key cannot be exported (stronger security, but cannot be backed up)
- Without `-SkipExport`: prompts to export `.cer` and `.pfx` files
- Attaches certificate to application `keyCredentials`
- Replaces existing key credentials (Graph API limitation)

## Output Files (when exported)

- `AuditWindowsCert.cer` (public key)
- `AuditWindowsCert.pfx` (private key, password protected)
