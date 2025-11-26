# Get-AuditWindowsApplication

Retrieves an existing application registration by display name.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DisplayName` | string | Yes | Application display name |

## Returns

Application object or `$null` if not found.

## Example

```powershell
$app = Get-AuditWindowsApplication -DisplayName 'Audit Windows'
if ($app) {
  Write-Host "Found app: $($app.AppId)"
}
```
