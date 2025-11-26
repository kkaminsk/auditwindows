# Get-ManagedDeviceByAadId

Retrieves Intune managed device info by Azure AD device ID.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `azureId` | string | Yes | Azure AD device ID |

## Returns

Single managed device object with:
- `userPrincipalName`
- `lastSyncDateTime`
- `azureADDeviceId`

Returns `$null` if device not found in Intune.

## Example

```powershell
$md = Get-ManagedDeviceByAadId '12345678-1234-1234-1234-123456789012'
$md.lastSyncDateTime  # Last Intune check-in
```
