function Get-BitLockerKeysByDeviceId {
  <#
    .SYNOPSIS
    Retrieves BitLocker recovery key metadata for a device.

    .DESCRIPTION
    Queries Microsoft Graph for BitLocker recovery key metadata associated with
    the specified Azure AD device ID. Returns key metadata (ID, volume type,
    created date) but NOT the actual recovery keys for security.

    Uses cmdlet if available, falls back to REST API otherwise.
    Treats 404 (not found) as non-fatal, returning empty array.

    .PARAMETER azureId
    The Azure AD device ID (GUID) to query BitLocker keys for.

    .OUTPUTS
    Array of BitLocker recovery key metadata objects with properties:
    - id: Key identifier
    - deviceId: Associated device ID
    - volumeType: OperatingSystemVolume or FixedDataVolume
    - createdDateTime: When the key was backed up

    .EXAMPLE
    $keys = Get-BitLockerKeysByDeviceId -azureId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    Returns BitLocker key metadata for the specified device.

    .NOTES
    Requires BitLockerKey.ReadBasic.All permission.
  #>
  [CmdletBinding()]
  param([string]$azureId)
  Invoke-GraphWithRetry -OperationName 'Get-MgInformationProtectionBitlockerRecoveryKey' -Resource "GET /informationProtection/bitlocker/recoveryKeys?`$select=id,deviceId,createdDateTime,volumeType&`$filter=deviceId eq '$azureId'" -NonFatalStatusCodes @(404) -NonFatalReturn @() -Script {
    if (Get-Command Get-MgInformationProtectionBitlockerRecoveryKey -ErrorAction SilentlyContinue) {
      Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$azureId'" -Property 'id','deviceId','createdDateTime','volumeType' -All -ErrorAction Stop
    } else {
      Invoke-GraphGetAll "/informationProtection/bitlocker/recoveryKeys?`$select=id,deviceId,createdDateTime,volumeType&`$filter=deviceId eq '$azureId'"
    }
  }
}
