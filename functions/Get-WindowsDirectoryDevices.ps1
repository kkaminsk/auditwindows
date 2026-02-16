function Get-WindowsDirectoryDevices {
  [CmdletBinding()]
  param()
  <#
    .SYNOPSIS
    Retrieves all Windows devices from Entra ID directory.

    .DESCRIPTION
    Queries Microsoft Graph for all devices with operatingSystem = 'Windows'.
    Returns device identity information including object ID, device ID,
    display name, and enabled status.

    Uses cmdlet if available, falls back to REST API otherwise.
    Handles pagination automatically to retrieve all devices.

    .OUTPUTS
    Array of device objects with properties:
    - id: Directory object ID
    - displayName: Device name
    - deviceId: Azure AD device ID (used for BitLocker/LAPS lookups)
    - accountEnabled: Whether the device account is enabled
    - operatingSystem: Always 'Windows' (filtered)

    .EXAMPLE
    $devices = Get-WindowsDirectoryDevices
    Returns all Windows devices from the directory.

    .NOTES
    Requires Device.Read.All permission.
  #>
  Invoke-GraphWithRetry -OperationName 'Get-MgDevice' -Resource "GET /devices?`$select=id,displayName,deviceId,accountEnabled,operatingSystem&`$filter=operatingSystem eq 'Windows'" -Script {
    if (Get-Command Get-MgDevice -ErrorAction SilentlyContinue) {
      Get-MgDevice -Filter "operatingSystem eq 'Windows'" -All -ErrorAction Stop
    } else {
      Invoke-GraphGetAll "/devices?`$select=id,displayName,deviceId,accountEnabled,operatingSystem&`$filter=operatingSystem eq 'Windows'"
    }
  }
}
