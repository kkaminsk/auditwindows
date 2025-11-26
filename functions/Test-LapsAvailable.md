# Test-LapsAvailable

Checks if LAPS credentials exist for a device.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `deviceName` | string | Yes | Device display name |

## Returns

`$true` if LAPS credentials exist, `$false` otherwise.

## Notes

- Does NOT retrieve the actual LAPS password
- Uses `DeviceLocalCredential.ReadBasic.All` scope
- 404 responses treated as "no LAPS" (non-fatal)

## Example

```powershell
if (Test-LapsAvailable 'DESKTOP-ABC123') {
  Write-Host "LAPS is configured"
}
```
