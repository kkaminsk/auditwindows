# Get-WindowsDirectoryDevices

Retrieves all Windows devices from Entra ID directory.

## Parameters

None.

## Returns

Array of device objects with properties:
- `id` (directory object ID)
- `displayName`
- `deviceId` (Azure AD device ID)
- `accountEnabled`
- `operatingSystem`

## Behavior

- Uses `Get-MgDevice` cmdlet if available
- Falls back to REST API via `Invoke-GraphGetAll`
- Filters by `operatingSystem eq 'Windows'`
- Handles pagination automatically

## Example

```powershell
$devices = Get-WindowsDirectoryDevices
```
