function Get-ManagedDeviceByAadId {
  param([string]$azureId)
  Invoke-GraphWithRetry -OperationName 'Get-MgDeviceManagementManagedDevice' -Resource "GET /deviceManagement/managedDevices?`$select=userPrincipalName,lastSyncDateTime,azureADDeviceId&`$filter=azureADDeviceId eq '$azureId'" -Script {
    if (Get-Command Get-MgDeviceManagementManagedDevice -ErrorAction SilentlyContinue) {
      Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$azureId'" -All -ErrorAction Stop
    } else {
      Invoke-GraphGetAll "/deviceManagement/managedDevices?`$select=userPrincipalName,lastSyncDateTime,azureADDeviceId&`$filter=azureADDeviceId eq '$azureId'"
    }
  } | Select-Object -First 1
}
