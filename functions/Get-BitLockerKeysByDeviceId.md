# Get-BitLockerKeysByDeviceId

Retrieves BitLocker recovery key metadata for a device.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `azureId` | string | Yes | Azure AD device ID |

## Returns

Array of recovery key objects with:
- `id`
- `deviceId`
- `createdDateTime`
- `volumeType` (OperatingSystemVolume, FixedDataVolume)

Returns empty array `@()` if no keys found (404 is non-fatal).

## Notes

- Does NOT retrieve actual recovery key values (uses `ReadBasic.All`)
- Only returns metadata for audit purposes

## Example

```powershell
$keys = Get-BitLockerKeysByDeviceId '12345678-1234-1234-1234-123456789012'
$osKey = $keys | Where-Object { $_.volumeType -match 'OperatingSystem' }
```
