# Write-AuditWindowsSummary

Outputs provisioning summary to console and JSON file.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Summary` | psobject | Yes | Summary record from `New-AuditWindowsSummaryRecord` |
| `SkipFileExport` | switch | No | Skip JSON file export |
| `OutputPath` | string | No | Custom output path (default: `~\AuditWindowsAppSummary.json`) |

## Output

Console:
- Application ID
- Tenant ID
- Certificate thumbprint and expiry
- Logo upload status

File: `AuditWindowsAppSummary.json`

## Behavior

- Opens Entra Portal to app's credentials blade
- Provides URL if browser fails to open
