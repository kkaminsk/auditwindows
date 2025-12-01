# Connect-GraphInteractive

Connects to Microsoft Graph with delegated authentication using a dedicated app registration.

## Parameters

None. Uses script-scope variables:
- `$script:AppDisplayName` - App registration name (default: "Audit Windows")
- `$script:TenantId` - Target tenant ID
- `$script:UseDeviceCode` - Use device code flow instead of browser

## Scopes Requested

- `Device.Read.All`
- `BitLockerKey.ReadBasic.All`
- `DeviceLocalCredential.ReadBasic.All`
- `DeviceManagementManagedDevices.Read.All`

## Behavior

1. Always looks up dedicated app registration (default: "Audit Windows")
2. Uses `-AppDisplayName` parameter to specify a different app name
3. If `-UseDeviceCode`: Uses device code flow instead of browser popup
4. Logs connection details (Tenant, Account, ClientId)
5. Outputs scopes as bulleted list

## Errors

- **Throws if dedicated app not found** - Run `Setup-AuditWindowsApp.ps1` first
- Throws on authentication failure

## Notes

This script does NOT fall back to the default Microsoft Graph PowerShell app. A custom app registration is required.
