# Invoke-GraphGetAll

Performs a paginated GET request to Microsoft Graph, following `@odata.nextLink` to retrieve all results.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RelativeUri` | string | Yes | Relative URI path (e.g., `/devices`) |

## Returns

Array of all items from the paginated response.

## Behavior

- Follows `@odata.nextLink` until all pages are retrieved
- Returns `value` array contents for collection responses
- Returns single object as array for non-collection responses

## Example

```powershell
$allDevices = Invoke-GraphGetAll "/devices?`$filter=operatingSystem eq 'Windows'"
```
