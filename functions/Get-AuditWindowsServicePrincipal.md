# Get-AuditWindowsServicePrincipal

Retrieves or creates a service principal for an application.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `AppId` | string | Yes | Application (client) ID |

## Returns

Service principal object.

## Behavior

- Returns existing SP if found
- Creates new SP if not found

## Example

```powershell
$sp = Get-AuditWindowsServicePrincipal -AppId $app.AppId
```
