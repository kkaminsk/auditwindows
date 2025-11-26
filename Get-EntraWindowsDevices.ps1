#Requires -Version 7.0
[CmdletBinding()]
param(
  [string]$OutputPath,
  [switch]$ExportCSV,
  [switch]$UseDeviceCode,
  [int]$MaxDevices,
  [switch]$UseAppAuth,
  [switch]$CreateAppIfMissing,
  [string]$AppName = 'WindowsAuditApp',
  [string]$AppDisplayName = 'Audit Windows',
  [string]$TenantId,
  [string]$CertSubject,
  [switch]$SkipModuleImport,
  [string]$DeviceName
)

$start = Get-Date
$ts = $start.ToString('yyyy-MM-dd-HH-mm')
$docs = if ($OutputPath) { $OutputPath } else { [Environment]::GetFolderPath('MyDocuments') }
if (-not (Test-Path -LiteralPath $docs)) { New-Item -ItemType Directory -Path $docs -Force | Out-Null }
$script:logPath = Join-Path $docs "WindowsAudit-$ts.log"
$xmlPath = Join-Path $docs "WindowsAudit-$ts.xml"
$csvPath = Join-Path $docs "WindowsAudit-$ts.csv"

# Load functions from .\functions folder
$functionsPath = Join-Path -Path $PSScriptRoot -ChildPath 'functions'
if (Test-Path -Path $functionsPath) {
  Get-ChildItem -Path $functionsPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}


Write-Log "Script start. OutputPath=$docs"

# Note: All functions (Write-Log, Invoke-GraphGet, Invoke-GraphGetAll, Invoke-GraphWithRetry,
#       Import-GraphModuleIfNeeded, Connect-GraphInteractive, Initialize-AppRegistrationAndConnect,
#       Get-WindowsDirectoryDevices, Get-ManagedDeviceByAadId, Get-BitLockerKeysByDeviceId,
#       Test-LapsAvailable, New-AuditXml, Add-TextNode) are now loaded from .\functions folder.

if (-not $SkipModuleImport) {
  Import-GraphModuleIfNeeded
} else {
  Write-Log "Skipping module import due to -SkipModuleImport" 'INFO'
  Write-Host "Skipping module import by request."
}
if ($UseAppAuth) {
  if (-not $TenantId -or $TenantId.Trim() -eq '') { throw "-TenantId is required when using -UseAppAuth." }
  Initialize-AppRegistrationAndConnect -Tenant $TenantId -Name $AppName -Create:$CreateAppIfMissing -Subject $CertSubject
} else {
  Connect-GraphInteractive
}

Write-Host "Querying Windows devices from Entra ID..."
Write-Log "Querying Windows devices from Entra ID..." 'INFO'
$ctxMode = Get-MgContext
Write-Log ("Auth mode: {0} | Tenant={1} | ClientId={2} | Account={3}" -f $ctxMode.AuthType, $ctxMode.TenantId, $ctxMode.ClientId, $ctxMode.Account) 'INFO'
$devices = Get-WindowsDirectoryDevices
if ($DeviceName) {
  $devices = $devices | Where-Object { $_.DisplayName -eq $DeviceName }
  Write-Log ("Filtering devices by name '{0}'. Matched: {1}" -f $DeviceName, ($devices | Measure-Object).Count) 'INFO'
}
Write-Log "Retrieved $($devices.Count) Windows devices." 'INFO'
Write-Host ("Retrieved {0} Windows devices." -f $devices.Count)
if ($MaxDevices -gt 0 -and $devices.Count -gt $MaxDevices) {
  $devices = $devices | Select-Object -First $MaxDevices
  Write-Log "Limiting processing to first $MaxDevices devices as requested." 'INFO'
  Write-Host ("Limiting processing to first {0} devices." -f $MaxDevices)
}

$xml = New-AuditXml
$root = $xml.DocumentElement
$summary = @()

$idx=0
foreach ($d in $devices) {
  $idx++
  Write-Log "Processing $idx/$($devices.Count): $($d.DisplayName) [$($d.Id)]"
  Write-Host ("Processing {0}/{1}: {2} [{3}]" -f $idx, $devices.Count, $d.DisplayName, $d.Id)
  $pct = [int](($idx / [double]$devices.Count) * 100)
  Write-Progress -Activity 'Exporting devices' -Status ("Processing {0}/{1}: {2}" -f $idx,$devices.Count,$d.DisplayName) -PercentComplete $pct
  $aadId = if ($d.PSObject.Properties.Name -contains 'DeviceId' -and $d.DeviceId) { $d.DeviceId } else { $d.Id }
  Write-Log ("Device identifiers: ObjectId={0} AzureAdDeviceId={1}" -f $d.Id, $aadId) 'DEBUG'
  $md = Get-ManagedDeviceByAadId $aadId
  $keys = @()
  try { $keys = Get-BitLockerKeysByDeviceId $aadId } catch { Write-Log "BitLocker lookup failed for $($d.Id) (aadId): $_" 'WARN' }
  if (($null -eq $keys) -or ($keys.Count -eq 0)) {
    if ($aadId -ne $d.Id) {
      Write-Log ("No BitLocker keys found with AzureAdDeviceId={0}. Falling back to ObjectId={1}." -f $aadId, $d.Id) 'DEBUG'
      try { $keys = Get-BitLockerKeysByDeviceId $d.Id } catch { Write-Log "BitLocker fallback lookup failed for $($d.Id) (objectId): $_" 'WARN' }
    }
  }
  Write-Log ("BitLocker keys count for device {0}: {1}" -f $d.Id, ($(if ($keys) { $keys.Count } else { 0 }))) 'DEBUG'
  $lapsAvail = $false; try { $lapsAvail = Test-LapsAvailable $d.DisplayName } catch { Write-Log "LAPS lookup failed for $($d.Id): $_" 'WARN' }

  $osBacked=$false; $osTime=$null; $dataBacked=$false; $dataTime=$null
  foreach ($k in ($keys | ForEach-Object { $_ })) {
    # Extract properties from typed members or AdditionalProperties (SDK versions differ)
    $vtRaw = $null
    $dtRaw = $null
    if ($k.PSObject.Properties.Name -contains 'VolumeType' -and $k.VolumeType) { $vtRaw = $k.VolumeType }
    elseif ($k.AdditionalProperties -and $k.AdditionalProperties.ContainsKey('volumeType')) { $vtRaw = $k.AdditionalProperties.volumeType }
    if ($k.PSObject.Properties.Name -contains 'CreatedDateTime' -and $k.CreatedDateTime) { $dtRaw = $k.CreatedDateTime }
    elseif ($k.AdditionalProperties -and $k.AdditionalProperties.ContainsKey('createdDateTime')) { $dtRaw = $k.AdditionalProperties.createdDateTime }

    $vt = if ($vtRaw) { $vtRaw.ToString().ToLowerInvariant() } else { $null }
    # Normalize volume type across variants ('...Volume' vs '...Drive') and numeric enums
    if ($vt -match 'operatingsystem(volume|drive)' -or $vt -eq 'os' -or $vt -eq '1' -or -not $vt) {
      $osBacked = $true
      if ($dtRaw) { $osTime = $dtRaw }
    }
    elseif ($vt -match 'fixeddata(volume|drive)' -or $vt -eq 'data' -or $vt -eq '2') {
      $dataBacked = $true
      if ($dtRaw) { $dataTime = $dtRaw }
    }
    Write-Log ("BitLocker key parsed: vt='{0}' dt='{1}' for device {2}" -f $vtRaw, $dtRaw, $d.Id) 'DEBUG'
  }

  $devEl = $xml.CreateElement('Device'); $root.AppendChild($devEl)|Out-Null
  Add-TextNode $xml $devEl 'Name' $d.DisplayName
  Add-TextNode $xml $devEl 'DeviceID' $d.Id
  Add-TextNode $xml $devEl 'AzureAdDeviceId' $aadId
  Add-TextNode $xml $devEl 'Enabled' ([string]$d.AccountEnabled)
  Add-TextNode $xml $devEl 'UserPrincipalName' ($md.UserPrincipalName)
  Add-TextNode $xml $devEl 'MDM' ($(if ($md) {'Microsoft Intune'}))
  $last=$null; if ($md -and $md.LastSyncDateTime) { $last = (Get-Date $md.LastSyncDateTime).ToUniversalTime().ToString('o') }
  $activity = if ($last) { if ((Get-Date) - (Get-Date $md.LastSyncDateTime) -lt ([TimeSpan]::FromDays(30))) {'Active'} else {'Inactive'} } else { $null }
  Add-TextNode $xml $devEl 'Activity' $activity
  Add-TextNode $xml $devEl 'LastCheckIn' $last

  $blEl=$xml.CreateElement('BitLocker'); $devEl.AppendChild($blEl)|Out-Null
  $os=$xml.CreateElement('Drive'); $a=$xml.CreateAttribute('type'); $a.Value='OperatingSystem'; $os.Attributes.Append($a)|Out-Null; $b=$xml.CreateElement('BackedUp'); $b.InnerText = if ($osTime) { (Get-Date $osTime).ToUniversalTime().ToString('o') } elseif ($osBacked) {'true'} else {'false'}; $os.AppendChild($b)|Out-Null; $e=$xml.CreateElement('Encrypted'); $e.InnerText = if ($osTime -or $osBacked) {'true'} else {'false'}; $os.AppendChild($e)|Out-Null; $blEl.AppendChild($os)|Out-Null
  $dd=$xml.CreateElement('Drive'); $a2=$xml.CreateAttribute('type'); $a2.Value='Data'; $dd.Attributes.Append($a2)|Out-Null; $b2=$xml.CreateElement('BackedUp'); $b2.InnerText = if ($dataTime) { (Get-Date $dataTime).ToUniversalTime().ToString('o') } elseif ($dataBacked) {'true'} else {'false'}; $dd.AppendChild($b2)|Out-Null; $e2=$xml.CreateElement('Encrypted'); $e2.InnerText = if ($dataTime -or $dataBacked) {'true'} else {'false'}; $dd.AppendChild($e2)|Out-Null; $blEl.AppendChild($dd)|Out-Null

  $laps=$xml.CreateElement('LAPS'); $devEl.AppendChild($laps)|Out-Null
  Add-TextNode $xml $laps 'Available' ($(if ($lapsAvail) {'true'} else {'false'}))
  Add-TextNode $xml $laps 'Retrieved' 'false'

  $summary += [pscustomobject]@{
    Name=$d.DisplayName; DeviceID=$d.Id; Enabled=$d.AccountEnabled; UserPrincipalName=$md.UserPrincipalName; MDM=$(if($md){'Microsoft Intune'}); Activity=$activity; LastCheckIn=$last; BitLockerOSBackedUp=$osBacked; BitLockerDataBackedUp=$dataBacked; BitLockerOSEncrypted=($osTime -or $osBacked); BitLockerDataEncrypted=($dataTime -or $dataBacked); LAPSAvailable=$lapsAvail
  }
  $deviceName = if ($d.DisplayName) { $d.DisplayName } else { $d.Id }
  Write-Host ("{0} exported" -f $deviceName)
}

$xml.Save($xmlPath); Write-Log "XML written: $xmlPath"; Write-Host ("XML written: {0}" -f $xmlPath)
if ($ExportCSV) { $summary | Export-Csv -NoTypeInformation -Path $csvPath; Write-Log "CSV written: $csvPath"; Write-Host ("CSV written: {0}" -f $csvPath) }

$durationSec = [int]((Get-Date)-$start).TotalSeconds
Write-Log ("Script end. Duration={0}s" -f $durationSec)
Write-Host ("Completed. Duration={0}s" -f $durationSec)

