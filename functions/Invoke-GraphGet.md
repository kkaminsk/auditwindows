# Invoke-GraphGet

Performs a single GET request to Microsoft Graph v1.0 API.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RelativeUri` | string | Yes | Relative URI path (e.g., `/devices`) |

## Returns

PSObject containing the Graph API response.

## Example

```powershell
$result = Invoke-GraphGet "/devices?`$filter=operatingSystem eq 'Windows'"
```

## Notes

- Prepends `https://graph.microsoft.com/v1.0` to the URI
- Does not handle pagination; use `Invoke-GraphGetAll` for collections
