# Confirm-AuditWindowsAction

Prompts for user confirmation before proceeding.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Message` | string | Yes | Prompt message |
| `Force` | switch | No | Skip confirmation |

## Behavior

- If `-Force`: Returns immediately
- Otherwise: Prompts `{Message} (y/N)`
- Throws if user doesn't confirm

## Example

```powershell
Confirm-AuditWindowsAction -Message 'Create application?' -Force:$Force
```
