# Connect-AuditWindowsGraph

Connects to Microsoft Graph with admin scopes for app provisioning.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Reauth` | switch | No | Force re-authentication |
| `TenantId` | string | No | Target tenant ID |

## Scopes Requested

- `Application.ReadWrite.All`
- `AppRoleAssignment.ReadWrite.All`

## Returns

`Microsoft.Graph.PowerShell.Models.MicrosoftGraphContext`

## Behavior

- Reuses existing session if valid
- Opens browser for interactive auth
- Requires Global Admin or Application Admin

## Used By

`Setup-AuditWindowsApp.ps1`
