# Write-Log

Writes a timestamped log entry to file and outputs to the appropriate PowerShell stream.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Message` | string | Yes | - | The message to log |
| `Level` | string | No | `INFO` | Log level: `INFO`, `WARN`, `ERROR`, `DEBUG` |

## Behavior

- Writes to `$script:logPath` with format: `[YYYY-MM-DD HH:mm:ss] LEVEL: Message`
- `ERROR` → `Write-Error`
- `WARN` → `Write-Warning`
- `DEBUG`/`INFO` → `Write-Verbose`

## Example

```powershell
Write-Log "Connected successfully" 'INFO'
Write-Log "Permission denied" 'ERROR'
```
