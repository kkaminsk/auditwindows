# Set-AuditWindowsPermissions

Configures and grants Microsoft Graph application permissions.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Application` | object | Yes | Application object |
| `ServicePrincipal` | object | Yes | Service principal object |

## Permissions Configured

- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

## Behavior

1. Builds `RequiredResourceAccess` structure
2. Updates application with permissions
3. Calls `Grant-AuditWindowsConsent` to grant admin consent
