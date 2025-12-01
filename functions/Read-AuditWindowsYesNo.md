# Read-AuditWindowsYesNo

Prompts for a yes/no response with input validation.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Prompt` | string | Yes | The prompt message to display |
| `Default` | string | No | Default value if user presses Enter. Must be `'Y'` or `'N'` |

## Returns

`[bool]` - Returns `$true` for yes, `$false` for no.

## Behavior

- Displays prompt with hint based on default value:
  - `(Y/n)` when Default is 'Y'
  - `(y/N)` when Default is 'N'
  - `(y/n)` when no default
- Accepts 'y', 'yes', 'n', 'no' (case-insensitive)
- Re-prompts on invalid input
- Returns default value when user presses Enter (if default set)

## Examples

```powershell
# With default yes
$continue = Read-AuditWindowsYesNo -Prompt "Continue?" -Default 'Y'

# With default no
$overwrite = Read-AuditWindowsYesNo -Prompt "Overwrite existing file?" -Default 'N'

# No default (requires explicit answer)
$confirm = Read-AuditWindowsYesNo -Prompt "Are you sure?"
```

## Related Functions

- `Confirm-AuditWindowsAction` - Higher-level confirmation with `-Force` support
