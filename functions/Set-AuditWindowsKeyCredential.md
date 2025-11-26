# Set-AuditWindowsKeyCredential

Adds a certificate credential to the application.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Application` | object | Yes | - | Application object |
| `CertificateSubject` | string | No | `CN=AuditWindowsCert` | Certificate subject |
| `CertificateValidityInMonths` | int | No | 24 | Validity period |
| `ExistingCertificateThumbprint` | string | No | - | Use existing cert |

## Returns

Certificate object from `Cert:\CurrentUser\My`.

## Behavior

- Uses existing cert if thumbprint provided
- Otherwise generates self-signed certificate (2048-bit RSA, SHA256)
- Exports `.cer` and `.pfx` to user profile
- Attaches certificate to application `keyCredentials`

## Output Files

- `AuditWindowsCert.cer` (public key)
- `AuditWindowsCert.pfx` (private key, password protected)
