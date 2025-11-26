function Test-LapsAvailable {
  param([string]$deviceName)
  $r = Invoke-GraphWithRetry -OperationName 'GET /directory/deviceLocalCredentials' -Resource "GET /directory/deviceLocalCredentials?`$filter=deviceName eq '$deviceName'" -NonFatalStatusCodes @(404) -NonFatalReturn $null -Script {
    Invoke-GraphGet "/directory/deviceLocalCredentials?`$filter=deviceName eq '$deviceName'"
  }
  return ($r -and $r.value -and $r.value.Count -gt 0)
}
