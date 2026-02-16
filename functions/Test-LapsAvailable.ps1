function Test-LapsAvailable {
  <#
    .SYNOPSIS
    Checks if LAPS credentials are available for a device.

    .DESCRIPTION
    Queries Microsoft Graph to determine if Windows LAPS (Local Administrator
    Password Solution) credentials exist for the specified device. Only checks
    for existence; does NOT retrieve the actual password.

    Treats 404 (not found) as non-fatal, returning $false.

    .PARAMETER deviceName
    The display name of the device to check for LAPS credentials.

    .OUTPUTS
    Boolean. $true if LAPS credentials exist, $false otherwise.

    .EXAMPLE
    $hasLaps = Test-LapsAvailable -deviceName 'DESKTOP-ABC123'
    Returns $true if LAPS password exists for the device.

    .NOTES
    Requires DeviceLocalCredential.ReadBasic.All permission.
  #>
  [CmdletBinding()]
  param([string]$deviceName)
  $safeName = Protect-ODataFilterValue $deviceName
  $r = Invoke-GraphWithRetry -OperationName 'GET /directory/deviceLocalCredentials' -Resource "GET /directory/deviceLocalCredentials?`$filter=deviceName eq '$safeName'" -NonFatalStatusCodes @(404) -NonFatalReturn $null -Script {
    Invoke-GraphGet "/directory/deviceLocalCredentials?`$filter=deviceName eq '$safeName'"
  }
  return ($r -and $r.value -and $r.value.Count -gt 0)
}
