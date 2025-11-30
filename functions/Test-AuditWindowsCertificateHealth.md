# Test-AuditWindowsCertificateHealth

Checks the health and expiration status of the Audit Windows certificate used for app-only authentication.

## Syntax

```powershell
Test-AuditWindowsCertificateHealth
    [-CertificateSubject <string>]
    [-CertificateThumbprint <string>]
    [-WarningDaysBeforeExpiry <int>]
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-CertificateSubject` | string | `'CN=AuditWindowsCert'` | Subject name to search for in Cert:\CurrentUser\My |
| `-CertificateThumbprint` | string | — | Specific thumbprint to check (takes precedence over Subject) |
| `-WarningDaysBeforeExpiry` | int | `30` | Days before expiry to trigger a warning |

## Output

Returns a `PSCustomObject` with the following properties:

| Property | Type | Description |
|----------|------|-------------|
| `Healthy` | bool | `$true` if certificate is valid and not expiring within the warning threshold |
| `DaysUntilExpiry` | int | Days until certificate expires (negative if already expired) |
| `Certificate` | X509Certificate2 | The certificate object, or `$null` if not found |
| `Message` | string | Human-readable status message |

## Examples

### Basic health check

```powershell
$health = Test-AuditWindowsCertificateHealth
if (-not $health.Healthy) {
    Write-Warning $health.Message
}
```

### Custom warning threshold (60 days)

```powershell
Test-AuditWindowsCertificateHealth -WarningDaysBeforeExpiry 60
```

### Check specific certificate by thumbprint

```powershell
Test-AuditWindowsCertificateHealth -CertificateThumbprint 'ABC123DEF456...'
```

### Integration with scheduled monitoring

```powershell
$health = Test-AuditWindowsCertificateHealth -WarningDaysBeforeExpiry 14
if (-not $health.Healthy) {
    Send-MailMessage -To 'admin@contoso.com' -Subject 'Certificate Expiring' -Body $health.Message
}
```

## Health States

| State | Healthy | Description |
|-------|---------|-------------|
| **Not Found** | `$false` | Certificate not found in store |
| **Expired** | `$false` | Certificate has already expired |
| **Expiring Soon** | `$false` | Certificate expires within the warning threshold |
| **Healthy** | `$true` | Certificate is valid with sufficient time remaining |

## Related

- [Setup-AuditWindowsApp.ps1](../README.md#setup-auditwindowsappps1) - Regenerate expired certificates
- [Set-AuditWindowsKeyCredential](./Set-AuditWindowsKeyCredential.md) - Certificate creation function
