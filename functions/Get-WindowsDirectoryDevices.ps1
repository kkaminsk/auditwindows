function Get-WindowsDirectoryDevices {
  Invoke-GraphWithRetry -OperationName 'Get-MgDevice' -Resource "GET /devices?`$select=id,displayName,deviceId,accountEnabled,operatingSystem&`$filter=operatingSystem eq 'Windows'" -Script {
    if (Get-Command Get-MgDevice -ErrorAction SilentlyContinue) {
      Get-MgDevice -Filter "operatingSystem eq 'Windows'" -All -ErrorAction Stop
    } else {
      Invoke-GraphGetAll "/devices?`$select=id,displayName,deviceId,accountEnabled,operatingSystem&`$filter=operatingSystem eq 'Windows'"
    }
  }
}
