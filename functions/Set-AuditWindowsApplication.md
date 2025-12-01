# Set-AuditWindowsApplication

Creates or retrieves the Audit Windows application registration.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DisplayName` | string | Yes | Application display name |
| `TenantId` | string | Yes | Target tenant ID |

## Returns

Application object (refreshed from API).

## Behavior

- Creates new app if not found (single-tenant, `AzureADMyOrg`)
- Returns existing app if found
- Configures public client settings:
  - `IsFallbackPublicClient = $true`
  - Redirect URIs: `http://localhost`, `https://login.microsoftonline.com/common/oauth2/nativeclient`
  - Homepage URL: `https://github.com/kkaminsk/auditwindows`
- Auto-updates existing apps if settings are missing

## Example

```powershell
$app = Set-AuditWindowsApplication -DisplayName 'Audit Windows' -TenantId $tenantId
```
