# Confirm-AuditWindowsAction

Prompts for user confirmation before proceeding.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Message` | string | Yes | Prompt message |
| `Force` | switch | No | Skip confirmation |

## Behavior

- If `-Force`: Returns immediately (no prompt)
- Otherwise: Prompts `{Message} (Y/n)` with default Yes
- Throws `'Operation cancelled by user.'` if user enters 'n' or 'N'

## Example

```powershell
Confirm-AuditWindowsAction -Message 'Create application?' -Force:$Force
```
