# Invoke-GraphWithRetry

Executes a script block with retry logic for transient Graph API failures.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Script` | scriptblock | Yes | - | The code to execute |
| `MaxRetries` | int | No | 4 | Maximum retry attempts |
| `OperationName` | string | No | - | Operation name for logging |
| `Resource` | string | No | - | Resource path for logging |
| `NonFatalStatusCodes` | int[] | No | - | HTTP status codes to treat as non-fatal |
| `NonFatalReturn` | any | No | - | Value to return for non-fatal errors |

## Behavior

- Retries on HTTP 429, 502, 503, 504 and timeout errors
- Respects `Retry-After` header
- Exponential backoff: 4s, 8s, 16s, 32s, 60s (max)
- Logs attempts, successes, retries, and failures

## Example

```powershell
$devices = Invoke-GraphWithRetry -OperationName 'GetDevices' -Script {
  Get-MgDevice -Filter "operatingSystem eq 'Windows'" -All
}

# With non-fatal 404
$keys = Invoke-GraphWithRetry -NonFatalStatusCodes @(404) -NonFatalReturn @() -Script {
  Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$id'"
}
```
