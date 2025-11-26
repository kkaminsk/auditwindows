function Get-ManagedDeviceByAadId {
  <#
    .SYNOPSIS
    Retrieves Intune managed device information by Azure AD device ID.

    .DESCRIPTION
    Queries Microsoft Graph for the Intune managed device record associated with
    the specified Azure AD device ID. Returns the first matching device with
    user principal name and last sync information.

    Uses cmdlet if available, falls back to REST API otherwise.

    .PARAMETER azureId
    The Azure AD device ID (GUID) to look up in Intune.

    .OUTPUTS
    Managed device object with properties:
    - userPrincipalName: Primary user of the device
    - lastSyncDateTime: Last Intune check-in time
    - azureADDeviceId: The Azure AD device ID

    .EXAMPLE
    $device = Get-ManagedDeviceByAadId -azureId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    Returns the Intune managed device record for the specified Azure AD device.

    .NOTES
    Requires DeviceManagementManagedDevices.Read.All permission.
    Returns $null if device is not Intune-managed.
  #>
  param([string]$azureId)
  Invoke-GraphWithRetry -OperationName 'Get-MgDeviceManagementManagedDevice' -Resource "GET /deviceManagement/managedDevices?`$select=userPrincipalName,lastSyncDateTime,azureADDeviceId&`$filter=azureADDeviceId eq '$azureId'" -Script {
    if (Get-Command Get-MgDeviceManagementManagedDevice -ErrorAction SilentlyContinue) {
      Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$azureId'" -All -ErrorAction Stop
    } else {
      Invoke-GraphGetAll "/deviceManagement/managedDevices?`$select=userPrincipalName,lastSyncDateTime,azureADDeviceId&`$filter=azureADDeviceId eq '$azureId'"
    }
  } | Select-Object -First 1
}
