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
  [string]$TenantId,
  [string]$CertSubject,
  [switch]$SkipModuleImport,
  [string]$DeviceName
)

$start = Get-Date
$ts = $start.ToString('yyyy-MM-dd-HH-mm')
$docs = if ($OutputPath) { $OutputPath } else { [Environment]::GetFolderPath('MyDocuments') }
if (-not (Test-Path -LiteralPath $docs)) { New-Item -ItemType Directory -Path $docs -Force | Out-Null }
$logPath = Join-Path $docs "WindowsAudit-$ts.log"
$xmlPath = Join-Path $docs "WindowsAudit-$ts.xml"
$csvPath = Join-Path $docs "WindowsAudit-$ts.csv"

function Write-Log {
  param([Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level='INFO')
  $line = ("[{0}] {1}: {2}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message)
  Add-Content -LiteralPath $logPath -Value $line
  switch ($Level) { 'ERROR' { Write-Error $Message } 'WARN' { Write-Warning $Message } 'DEBUG' { Write-Verbose $Message } default { Write-Verbose $Message } }
}

function Invoke-GraphGet {
  param([Parameter(Mandatory=$true)][string]$RelativeUri)
  $uri = "https://graph.microsoft.com/v1.0$RelativeUri"
  Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
}

function Invoke-GraphGetAll {
  param([Parameter(Mandatory=$true)][string]$RelativeUri)
  $uri = "https://graph.microsoft.com/v1.0$RelativeUri"
  $acc = @()
  while ($true) {
    $res = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
    if ($null -ne $res.value) {
      $acc += $res.value
      if ($res.'@odata.nextLink') { $uri = $res.'@odata.nextLink' } else { break }
    } else {
      # not a collection response; return as single-element array
      $acc += $res
      break
    }
  }
  return $acc
}

Write-Log "Script start. OutputPath=$docs"

function Import-GraphModuleIfNeeded {
  # Prefer targeted submodules to avoid meta-module assembly conflicts
  $neededModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Identity.DirectoryManagement',
    'Microsoft.Graph.DeviceManagement',
    'Microsoft.Graph.InformationProtection'
  )
  # Only load app management modules when app-only auth/provisioning is requested
  if ($UseAppAuth -or $CreateAppIfMissing) {
    $neededModules += @('Microsoft.Graph.Applications','Microsoft.Graph.ServicePrincipals')
  }
  # If keys exist but none classified, assume OS backed up to avoid false negatives
  if (($keys -and $keys.Count -gt 0) -and (-not $osBacked -and -not $dataBacked)) {
    $osBacked = $true
    Write-Log ("BitLocker keys exist but volumeType was ambiguous; marking OS as backed up for device {0}" -f $d.Id) 'WARN'
  }
  $cmdChecks = @{
    'Microsoft.Graph.Authentication'               = @('Connect-MgGraph','Get-MgContext')
    'Microsoft.Graph.Applications'                 = @('New-MgApplication','Update-MgApplication','Get-MgApplication')
    'Microsoft.Graph.ServicePrincipals'            = @('New-MgServicePrincipal','Get-MgServicePrincipal','New-MgServicePrincipalAppRoleAssignment','Get-MgServicePrincipalAppRoleAssignment')
    'Microsoft.Graph.Identity.DirectoryManagement' = @('Get-MgDevice','Get-MgDirectoryDeviceLocalCredential')
    'Microsoft.Graph.DeviceManagement'             = @('Get-MgDeviceManagementManagedDevice')
    'Microsoft.Graph.InformationProtection'        = @('Get-MgInformationProtectionBitlockerRecoveryKey')
  }
  foreach ($m in $neededModules) {
    $checks = $cmdChecks[$m]
    if ($checks) {
      $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
      if ($missing.Count -eq 0) {
        Write-Log ("Commands already available for {0}; skipping import." -f $m) 'INFO'
        Write-Host ("Commands already available for {0}; skipping import." -f $m)
        continue
      }
    }
    if (-not (Get-Module -ListAvailable -Name $m)) {
      Write-Log ("Installing {0} to CurrentUser..." -f $m) 'WARN'
      try { Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch { Write-Log ("Install failed for {0}: {1}" -f $m, $_) 'ERROR'; throw }
    }
    Write-Host ("Loading module: {0}" -f $m)
    try {
      Import-Module $m -ErrorAction Stop
      $loaded = Get-Module -Name $m | Select-Object -First 1
      if ($loaded) { Write-Log ("Loaded {0} v{1} from {2}" -f $loaded.Name, $loaded.Version, $loaded.Path) 'INFO' }
    } catch {
      $errText = $_.ToString()
      Write-Log ("Failed to import {0}: {1}" -f $m, $errText) 'ERROR'
      # If assemblies are already loaded but commands are present, proceed
      if ($errText -match 'Assembly with same name is already loaded') {
        $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($missing.Count -eq 0) {
          Write-Log ("Assembly already loaded for {0}; required commands present. Proceeding." -f $m) 'WARN'
          Write-Host ("Assembly already loaded for {0}; required commands present. Proceeding." -f $m)
          continue
        }
      }
      Write-Host ("ERROR importing {0}. Attempting import by explicit path..." -f $m) -ForegroundColor Red
      $latest = Get-Module -ListAvailable -Name $m | Sort-Object Version -Descending | Select-Object -First 1
      if ($latest) {
        try {
          Import-Module -FullyQualifiedName $latest.Path -ErrorAction Stop
          Write-Log ("Imported {0} by path: {1}" -f $m, $latest.Path) 'INFO'
        } catch {
          $errText2 = $_.ToString()
          Write-Log ("Import by path failed for {0}: {1}" -f $m, $errText2) 'ERROR'
          # Final fallback: if commands exist anyway, proceed; else throw
          $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
          if ($missing.Count -eq 0) {
            Write-Log ("Commands detected despite import error for {0}. Proceeding." -f $m) 'WARN'
            Write-Host ("Commands detected despite import error for {0}. Proceeding." -f $m)
          } else {
            throw
          }
        }
      } else {
        # No module found; if commands exist (from previous meta-module), proceed
        $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($missing.Count -eq 0) {
          Write-Log ("No installable module found for {0}, but commands are present. Proceeding." -f $m) 'WARN'
          Write-Host ("No installable module found for {0}, but commands are present. Proceeding." -f $m)
        } else {
          throw
        }
      }
    }
  }
  Write-Log "Graph submodules loaded." 'INFO'
  Write-Host "Graph submodules loaded."
}

function Invoke-GraphWithRetry {
  param(
    [scriptblock]$Script,
    [int]$MaxRetries=4,
    [string]$OperationName,
    [string]$Resource,
    [int[]]$NonFatalStatusCodes,
    $NonFatalReturn
  )
  $i=0
  while ($true) {
    if ($OperationName -or $Resource) { Write-Log "Graph call attempt $($i+1): op='$OperationName' resource='$Resource'" 'DEBUG' }
    $startAttempt = Get-Date
    try {
      $result = & $Script
      $elapsed = [int]((Get-Date) - $startAttempt).TotalMilliseconds
      if ($OperationName -or $Resource) { Write-Log "Graph call success: op='$OperationName' resource='$Resource' elapsedMs=$elapsed" 'DEBUG' }
      return $result
    } catch {
      $msg=$_.Exception.Message
      $code=$null; try { if ($_.Exception.Response.StatusCode) { $code=[int]$_.Exception.Response.StatusCode } } catch {}
      # Try to parse Status: 404 from the message text emitted by Graph cmdlets
      if (-not $code) { try { $m=[regex]::Match($msg,'Status:\s*(\d{3})'); if ($m.Success) { $code = [int]$m.Groups[1].Value } } catch {} }
      # If still no code but message indicates not found and caller treats 404 as non-fatal, honor that
      if (-not $code -and $NonFatalStatusCodes -and ($NonFatalStatusCodes -contains 404) -and ($msg -match '(?i)\bnot\s*found\b|\bcould not be found\b')) { $code = 404 }
      if ($NonFatalStatusCodes -and ($code -in $NonFatalStatusCodes)) {
        Write-Log "Graph call non-fatal (status=$code) op='$OperationName' resource='$Resource': $msg" 'DEBUG'
        return $NonFatalReturn
      }
      $retry=$code -in 429,502,503,504 -or $msg -match 'timeout|temporar|Too Many'
      $i++
      $wait=[Math]::Min(2*[Math]::Pow(2,$i),60)
      try {
        $headers = $_.Exception.Response.Headers
        if ($headers -and $headers['Retry-After']) { $wait = [int]$headers['Retry-After'] }
      } catch {}
      if ($i -le $MaxRetries -and $retry) {
        Write-Log "Graph call retry $i/$MaxRetries in $wait sec (status=$code) op='$OperationName' resource='$Resource' msg: $msg" 'WARN'
        Start-Sleep -Seconds $wait
        continue
      }
      Write-Log "Graph call failed (status=$code) op='$OperationName' resource='$Resource': $msg" 'ERROR'
      throw
    }
  }
}

function Connect-GraphInteractive {
  $scopes = 'Device.Read.All','BitLockerKey.Read.All','Directory.Read.All','DeviceLocalCredential.Read.All','DeviceManagementManagedDevices.Read.All'
  Write-Log "Connecting to Graph with scopes: $($scopes -join ', ')"
  Write-Host "Connecting to Microsoft Graph..."
  try {
    if ($UseDeviceCode) {
      Write-Host "Using device code flow for authentication."
      Connect-MgGraph -Scopes $scopes -UseDeviceCode -NoWelcome -ErrorAction Stop | Out-Null
    } else {
      Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null
    }
    $ctx = Get-MgContext
    Write-Log "Connected. Tenant=$($ctx.TenantId) Account=$($ctx.Account)" 'INFO'
    Write-Host ("Connected to Graph. Tenant={0} Account={1}" -f $ctx.TenantId, $ctx.Account)
  } catch {
    Write-Log "Failed to connect to Microsoft Graph. $_" 'ERROR'
    Write-Host "ERROR: Failed to connect to Microsoft Graph. See log for details." -ForegroundColor Red
    throw
  }
}

function Ensure-AppRegistrationAndConnect {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Tenant,
    [Parameter()][string]$Name = 'WindowsAuditApp',
    [Parameter()][switch]$Create,
    [Parameter()][string]$Subject
  )
  if (-not $Subject -or $Subject.Trim() -eq '') { $Subject = "CN=$Name" }
  Write-Host ("App-based auth requested. TenantId={0} AppName={1}" -f $Tenant, $Name)
  Write-Log ("App-based auth requested. TenantId={0} AppName={1}" -f $Tenant, $Name) 'INFO'

  $app = $null
  $cert = $null
  if ($Create) {
    Write-Host "Connecting (admin) to provision/ensure application (device code)..."
    $adminScopes = 'Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Directory.ReadWrite.All'
    Connect-MgGraph -UseDeviceCode -Scopes $adminScopes -NoWelcome -ErrorAction Stop | Out-Null
    $ctx = Get-MgContext
    Write-Log ("Admin connected for provisioning. Tenant={0}" -f $ctx.TenantId) 'INFO'

    $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource "GET /applications?$filter=displayName eq '$Name'" -Script { Get-MgApplication -Filter "displayName eq '$Name'" -All } | Select-Object -First 1
    if (-not $app) {
      Write-Host ("Creating application '{0}'..." -f $Name)
      $app = Invoke-GraphWithRetry -OperationName 'New-MgApplication' -Resource 'POST /applications' -Script { New-MgApplication -DisplayName $Name -SignInAudience 'AzureADMyOrg' }
      Write-Log ("Created application AppId={0} Id={1}" -f $app.AppId, $app.Id) 'INFO'
    } else {
      Write-Host ("Application exists. AppId={0}" -f $app.AppId)
    }

    $sp = Invoke-GraphWithRetry -OperationName 'Get-MgServicePrincipal' -Resource "GET /servicePrincipals?$filter=appId eq '$($app.AppId)'" -Script { Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -All } | Select-Object -First 1
    if (-not $sp) {
      Write-Host "Creating service principal for the application..."
      $sp = Invoke-GraphWithRetry -OperationName 'New-MgServicePrincipal' -Resource 'POST /servicePrincipals' -Script { New-MgServicePrincipal -AppId $app.AppId }
      Write-Log ("Created service principal Id={0}" -f $sp.Id) 'INFO'
    }

    $cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $Subject } | Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $cert) {
      Write-Host ("Creating self-signed certificate {0}..." -f $Subject)
      $cert = New-SelfSignedCertificate -Subject $Subject -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -NotAfter (Get-Date).AddYears(2)
      Write-Log ("Created certificate Thumbprint={0}" -f $cert.Thumbprint) 'INFO'
    } else {
      Write-Host ("Using existing certificate Thumbprint={0}" -f $cert.Thumbprint)
    }

    # Ensure cert on application keyCredentials (avoid duplicate by thumbprint)
    $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource "GET /applications?$filter=displayName eq '$Name'" -Script { Get-MgApplication -Filter "displayName eq '$Name'" -All } | Select-Object -First 1
    $thumbBytes = $cert.GetCertHash()
    $thumbB64 = [System.Convert]::ToBase64String($thumbBytes)
    $hasKey = $false
    foreach ($k in ($app.KeyCredentials | ForEach-Object { $_ })) {
      $existingB64 = if ($k.CustomKeyIdentifier) { [System.Convert]::ToBase64String($k.CustomKeyIdentifier) } else { $null }
      if ($existingB64 -eq $thumbB64) { $hasKey = $true; break }
    }
    if (-not $hasKey) {
      Write-Host "Adding certificate to application keyCredentials..."
      $keyObj = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphKeyCredential]::new()
      $keyObj.DisplayName = 'WindowsAuditCert'
      $keyObj.Type = 'AsymmetricX509Cert'
      $keyObj.Usage = 'Verify'
      # Byte[] for Key and CustomKeyIdentifier
      $keyObj.Key = $cert.RawData
      $keyObj.CustomKeyIdentifier = $thumbBytes
      $keyObj.StartDateTime = Get-Date
      $keyObj.EndDateTime = $cert.NotAfter
      $newKeys = @($app.KeyCredentials + $keyObj)
      Invoke-GraphWithRetry -OperationName 'Update-MgApplication' -Resource 'PATCH /applications/{id}' -Script { Update-MgApplication -ApplicationId $app.Id -KeyCredentials $newKeys } | Out-Null
      Write-Log "Certificate added to application." 'INFO'
      $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource 'GET /applications/{id}' -Script { Get-MgApplication -ApplicationId $app.Id }
    }

    # Grant app roles on Microsoft Graph
    $graphSp = Invoke-GraphWithRetry -OperationName 'Get-MgServicePrincipal' -Resource "GET /servicePrincipals?$filter=appId eq '00000003-0000-0000-c000-000000000000'" -Script { Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -All } | Select-Object -First 1
    $needed = @('Device.Read.All','Directory.Read.All','BitLockerKey.Read.All','DeviceLocalCredential.Read.All','DeviceManagementManagedDevices.Read.All')
    $assignments = Invoke-GraphWithRetry -OperationName 'Get-MgServicePrincipalAppRoleAssignment' -Resource 'GET /servicePrincipals/{id}/appRoleAssignments' -Script { Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All }
    foreach ($perm in $needed) {
      $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $perm -and $_.AllowedMemberTypes -contains 'Application' } | Select-Object -First 1
      if ($role) {
        $has = $assignments | Where-Object { $_.AppRoleId -eq $role.Id }
        if (-not $has) {
          Write-Host ("Granting application permission: {0}" -f $perm)
          Invoke-GraphWithRetry -OperationName 'New-MgServicePrincipalAppRoleAssignment' -Resource 'POST /servicePrincipals/{id}/appRoleAssignments' -Script { New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $graphSp.Id -AppRoleId $role.Id } | Out-Null
        }
      } else {
        Write-Log ("App role not found for {0}" -f $perm) 'WARN'
      }
    }
    Write-Host "Provisioning done."
    Disconnect-MgGraph | Out-Null
  } else {
    # No provisioning: find app and cert locally
    if (-not $Subject -or $Subject.Trim() -eq '') { $Subject = "CN=$Name" }
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $Subject } | Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $cert) { throw "Certificate not found in CurrentUser\\My with subject $Subject. Provide -CertSubject or run with -CreateAppIfMissing." }
    Connect-MgGraph -UseDeviceCode -Scopes 'Application.Read.All' -NoWelcome -ErrorAction Stop | Out-Null
    $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource "GET /applications?$filter=displayName eq '$Name'" -Script { Get-MgApplication -Filter "displayName eq '$Name'" -All } | Select-Object -First 1
    Disconnect-MgGraph | Out-Null
    if (-not $app) { throw "Application '$Name' not found. Use -CreateAppIfMissing to provision." }
  }

  Write-Host "Connecting to Graph with application (certificate)..."
  Connect-MgGraph -TenantId $Tenant -ClientId $app.AppId -CertificateThumbprint $cert.Thumbprint -NoWelcome -ErrorAction Stop | Out-Null
  $ctx2 = Get-MgContext
  Write-Log ("Connected (app-only). Tenant={0} AppId={1}" -f $ctx2.TenantId, $app.AppId) 'INFO'
  Write-Host ("Connected (app-only). Tenant={0} AppId={1}" -f $ctx2.TenantId, $app.AppId)
}

function Get-WindowsDirectoryDevices { Invoke-GraphWithRetry -OperationName 'Get-MgDevice' -Resource "GET /devices?`$select=id,displayName,deviceId,accountEnabled,operatingSystem&`$filter=operatingSystem eq 'Windows'" -Script { if (Get-Command Get-MgDevice -ErrorAction SilentlyContinue) { Get-MgDevice -Filter "operatingSystem eq 'Windows'" -All -ErrorAction Stop } else { Invoke-GraphGetAll "/devices?`$select=id,displayName,deviceId,accountEnabled,operatingSystem&`$filter=operatingSystem eq 'Windows'" } } }
function Get-ManagedDeviceByAadId($azureId) { Invoke-GraphWithRetry -OperationName 'Get-MgDeviceManagementManagedDevice' -Resource "GET /deviceManagement/managedDevices?`$select=userPrincipalName,lastSyncDateTime,azureADDeviceId&`$filter=azureADDeviceId eq '$azureId'" -Script { if (Get-Command Get-MgDeviceManagementManagedDevice -ErrorAction SilentlyContinue) { Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$azureId'" -All -ErrorAction Stop } else { Invoke-GraphGetAll "/deviceManagement/managedDevices?`$select=userPrincipalName,lastSyncDateTime,azureADDeviceId&`$filter=azureADDeviceId eq '$azureId'" } } | Select-Object -First 1 }
function Get-BitLockerKeysByDeviceId($azureId) { Invoke-GraphWithRetry -OperationName 'Get-MgInformationProtectionBitlockerRecoveryKey' -Resource "GET /informationProtection/bitlocker/recoveryKeys?`$select=id,deviceId,createdDateTime,volumeType&`$filter=deviceId eq '$azureId'" -NonFatalStatusCodes @(404) -NonFatalReturn @() -Script { if (Get-Command Get-MgInformationProtectionBitlockerRecoveryKey -ErrorAction SilentlyContinue) { Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$azureId'" -Property 'id','deviceId','createdDateTime','volumeType' -All -ErrorAction Stop } else { Invoke-GraphGetAll "/informationProtection/bitlocker/recoveryKeys?`$select=id,deviceId,createdDateTime,volumeType&`$filter=deviceId eq '$azureId'" } } }
function Test-LapsAvailable($azureId) { $r = Invoke-GraphWithRetry -OperationName 'Get-MgDirectoryDeviceLocalCredential' -Resource "GET /directory/deviceLocalCredentials/$azureId" -NonFatalStatusCodes @(404) -NonFatalReturn $null -Script { if (Get-Command Get-MgDirectoryDeviceLocalCredential -ErrorAction SilentlyContinue) { Get-MgDirectoryDeviceLocalCredential -DeviceLocalCredentialInfoId $azureId -ErrorAction Stop } else { Invoke-GraphGet "/directory/deviceLocalCredentials/$azureId" } }; return ($null -ne $r) }

function New-AuditXml { $xml = New-Object System.Xml.XmlDocument; $decl=$xml.CreateXmlDeclaration('1.0','UTF-8',$null); $xml.AppendChild($decl)|Out-Null; $root=$xml.CreateElement('WindowsAudit'); $xml.AppendChild($root)|Out-Null; return $xml }

function Add-TextNode($xml,$parent,$name,$value) { $n=$xml.CreateElement($name); if ($null -ne $value -and "$value" -ne '') { $n.InnerText = [string]$value }; $parent.AppendChild($n)|Out-Null }

if (-not $SkipModuleImport) {
  Import-GraphModuleIfNeeded
} else {
  Write-Log "Skipping module import due to -SkipModuleImport" 'INFO'
  Write-Host "Skipping module import by request."
}
if ($UseAppAuth) {
  if (-not $TenantId -or $TenantId.Trim() -eq '') { throw "-TenantId is required when using -UseAppAuth." }
  Ensure-AppRegistrationAndConnect -Tenant $TenantId -Name $AppName -Create:$CreateAppIfMissing -Subject $CertSubject
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
  $lapsAvail = $false; try { $lapsAvail = Test-LapsAvailable $aadId } catch { Write-Log "LAPS lookup failed for $($d.Id): $_" 'WARN' }

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
