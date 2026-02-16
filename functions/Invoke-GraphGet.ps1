function Invoke-GraphGet {
  <#
    .SYNOPSIS
    Executes a single GET request to Microsoft Graph API.

    .DESCRIPTION
    Sends a GET request to the Microsoft Graph v1.0 endpoint using the
    authenticated session. Returns the response as a PSObject.

    .PARAMETER RelativeUri
    The relative URI path (starting with /) to append to the Graph base URL.
    Example: "/devices" or "/users?$filter=displayName eq 'John'"

    .OUTPUTS
    PSObject containing the Graph API response.

    .EXAMPLE
    $result = Invoke-GraphGet "/me"
    Returns the current user's profile.

    .EXAMPLE
    $result = Invoke-GraphGet "/devices?`$filter=operatingSystem eq 'Windows'"
    Returns Windows devices (single page).

    .NOTES
    Does not handle pagination. Use Invoke-GraphGetAll for paginated results.
    Requires an active Microsoft Graph connection via Connect-MgGraph.
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory=$true)][string]$RelativeUri)
  $uri = "https://graph.microsoft.com/v1.0$RelativeUri"
  Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
}
