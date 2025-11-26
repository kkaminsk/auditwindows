function Invoke-GraphGetAll {
  <#
    .SYNOPSIS
    Executes a paginated GET request to Microsoft Graph API.

    .DESCRIPTION
    Sends GET requests to the Microsoft Graph v1.0 endpoint and automatically
    follows @odata.nextLink pagination to retrieve all results. Accumulates
    all items from the 'value' collection across all pages.

    .PARAMETER RelativeUri
    The relative URI path (starting with /) to append to the Graph base URL.
    Example: "/devices?$filter=operatingSystem eq 'Windows'"

    .OUTPUTS
    Array of all items from the paginated response.

    .EXAMPLE
    $allDevices = Invoke-GraphGetAll "/devices"
    Returns all devices, following pagination links automatically.

    .EXAMPLE
    $windowsDevices = Invoke-GraphGetAll "/devices?`$filter=operatingSystem eq 'Windows'"
    Returns all Windows devices across all pages.

    .NOTES
    Requires an active Microsoft Graph connection via Connect-MgGraph.
  #>
  param([Parameter(Mandatory=$true)][string]$RelativeUri)
  $uri = "https://graph.microsoft.com/v1.0$RelativeUri"
  $acc = @()
  while ($true) {
    $res = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
    if ($null -ne $res.value) {
      $acc += $res.value
      if ($res.'@odata.nextLink') { $uri = $res.'@odata.nextLink' } else { break }
    } else {
      # not a collection response; return as single-element array
      $acc += $res
      break
    }
  }
  return $acc
}
