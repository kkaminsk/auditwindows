function Set-AuditWindowsPermissions {
  <#
    .SYNOPSIS
    Configures Microsoft Graph application permissions for the Audit Windows app.
  #>
  param(
    [Parameter(Mandatory)]
    $Application,
    [Parameter(Mandatory)]
    $ServicePrincipal
  )

  $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
  $rawResourceAccess = Get-AuditWindowsGraphResourceAccess -ServicePrincipal $graphSp

  # Normalize the structure into a predictable array of hashtables
  $normalizedResourceAccess = @()
  foreach ($item in @($rawResourceAccess)) {
    if (-not $item) { continue }

    $resourceAppId = $null
    $accessList = $null

    if ($item -is [hashtable]) {
      $resourceAppId = $item['ResourceAppId']
      $accessList    = $item['ResourceAccess']
    }
    else {
      $resourceAppId = $item.ResourceAppId
      $accessList    = $item.ResourceAccess
    }

    if (-not $resourceAppId -or -not $accessList) { continue }

    $normalizedResourceAccess += @{
      ResourceAppId  = $resourceAppId
      ResourceAccess = $accessList
    }
  }

  if (-not $normalizedResourceAccess) {
    throw 'Unable to resolve Microsoft Graph application permissions. Ensure service principal app roles are available.'
  }

  Write-Host 'Configuring Microsoft Graph application permissions:' -ForegroundColor Cyan
  foreach ($perm in Get-AuditWindowsPermissionNames) {
    Write-Host " - $perm" -ForegroundColor Cyan
  }

  try {
    Update-MgApplication -ApplicationId $Application.Id -RequiredResourceAccess $normalizedResourceAccess -ErrorAction Stop | Out-Null
    Write-Host 'Permissions configured successfully.' -ForegroundColor Green
  }
  catch {
    throw "Failed to configure Graph permissions. Error: $($_.Exception.Message)"
  }

  # Identify the Microsoft Graph resource definition for consent
  $graphResource = $normalizedResourceAccess | Where-Object { $_['ResourceAppId'] -eq $graphSp.AppId } | Select-Object -First 1
  if (-not $graphResource) {
    throw 'Unable to identify Microsoft Graph resource access payload.'
  }

  $graphAccessList = $graphResource['ResourceAccess']
  Grant-AuditWindowsConsent -ServicePrincipal $ServicePrincipal -GraphServicePrincipal $graphSp -ResourceAccess $graphAccessList
}
