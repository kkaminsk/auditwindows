$d = Get-MgDevice -Filter "displayName eq 'DESKTOP-KIJL01G'" -All | Select-Object -First 1
$d.Id, $d.DeviceId

Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$($d.DeviceId)'" -All |
  Select-Object id, deviceId, createdDateTime, volumeType