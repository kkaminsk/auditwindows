# Set-AuditWindowsLogo

Uploads a logo to the application registration if `logo.jpg` exists.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Application` | object | Yes | Application object |
| `ScriptRoot` | string | Yes | Path to look for `logo.jpg` |

## Returns

`$true` if logo uploaded, `$false` otherwise.

## Behavior

- Looks for `logo.jpg` in `$ScriptRoot`
- Warns if not found (non-fatal)
- Uploads via `Set-MgApplicationLogo`

## Requirements

- JPEG format, under 100 KB
