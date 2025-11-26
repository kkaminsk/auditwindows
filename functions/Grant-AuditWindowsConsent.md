# Grant-AuditWindowsConsent

Grants admin consent for application permissions.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ServicePrincipal` | object | Yes | App's service principal |
| `GraphServicePrincipal` | object | Yes | Microsoft Graph SP |
| `ResourceAccess` | array | Yes | Permissions to consent |

## Behavior

- Skips already-consented permissions
- Creates `appRoleAssignment` for each permission
- Requires Global Admin or Privileged Role Admin

## Notes

Called by `Set-AuditWindowsPermissions`, not directly.
