# Disconnect-AuditWindowsGraph

Disconnects from Microsoft Graph and cleans up the session.

## Parameters

None.

## Returns

None (void).

## Behavior

- Checks if a Graph session exists before attempting to disconnect
- Silently handles any errors during disconnection
- Safe to call even if no session exists

## Example

```powershell
Disconnect-AuditWindowsGraph
```

Disconnects from the current Microsoft Graph session if one exists.

## Used By

`Setup-AuditWindowsApp.ps1`
