function Get-BitLockerKeysByDeviceId {
  param([string]$azureId)
  Invoke-GraphWithRetry -OperationName 'Get-MgInformationProtectionBitlockerRecoveryKey' -Resource "GET /informationProtection/bitlocker/recoveryKeys?`$select=id,deviceId,createdDateTime,volumeType&`$filter=deviceId eq '$azureId'" -NonFatalStatusCodes @(404) -NonFatalReturn @() -Script {
    if (Get-Command Get-MgInformationProtectionBitlockerRecoveryKey -ErrorAction SilentlyContinue) {
      Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$azureId'" -Property 'id','deviceId','createdDateTime','volumeType' -All -ErrorAction Stop
    } else {
      Invoke-GraphGetAll "/informationProtection/bitlocker/recoveryKeys?`$select=id,deviceId,createdDateTime,volumeType&`$filter=deviceId eq '$azureId'"
    }
  }
}
