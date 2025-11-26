function Connect-GraphInteractive {
  $scopes = 'Device.Read.All','BitLockerKey.ReadBasic.All','DeviceLocalCredential.ReadBasic.All','DeviceManagementManagedDevices.Read.All'
  Write-Log "Connecting to Graph with scopes: $($scopes -join ', ')"
  Write-Host "Connecting to Microsoft Graph..."
  
  # Always require dedicated app registration (default: 'Audit Windows')
  $appName = if ($script:AppDisplayName) { $script:AppDisplayName } else { 'Audit Windows' }
  Write-Host "Looking up dedicated '$appName' app registration..." -ForegroundColor Cyan
  Write-Log "Looking up dedicated app '$appName'" 'INFO'
  
  $clientId = $null
  $tenantId = $script:TenantId  # Use provided TenantId if available
  try {
    # First connect without scopes to query apps (user must have read access)
    Connect-MgGraph -Scopes 'Application.Read.All' -NoWelcome -ErrorAction Stop | Out-Null
    $lookupCtx = Get-MgContext
    if (-not $tenantId -and $lookupCtx.TenantId) {
      $tenantId = $lookupCtx.TenantId  # Capture tenant from lookup session
    }
    $dedicatedApp = Get-MgApplication -Filter "displayName eq '$appName'" -ErrorAction SilentlyContinue | Select-Object -First 1
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    
    if ($dedicatedApp) {
      $clientId = $dedicatedApp.AppId
      Write-Host "Found dedicated app: $($dedicatedApp.DisplayName) (ClientId: $clientId)" -ForegroundColor Green
      Write-Log "Found dedicated app ClientId=$clientId TenantId=$tenantId" 'INFO'
    } else {
      Write-Host ""
      Write-Host "ERROR: Application '$appName' not found in tenant." -ForegroundColor Red
      Write-Host ""
      Write-Host "To fix this, either:" -ForegroundColor Yellow
      Write-Host "  1. Run Setup-AuditWindowsApp.ps1 to create the default 'Audit Windows' app" -ForegroundColor Yellow
      Write-Host "  2. Specify an existing app with: -AppDisplayName 'YourAppName'" -ForegroundColor Yellow
      Write-Host ""
      Write-Log "Dedicated app '$appName' not found in tenant" 'ERROR'
      throw "Application '$appName' not found. Run Setup-AuditWindowsApp.ps1 first or specify -AppDisplayName."
    }
  } catch {
    if ($_.Exception.Message -match 'not found') { throw }
    Write-Log "Failed to look up dedicated app: $($_.Exception.Message)" 'ERROR'
    throw "Failed to look up application '$appName': $($_.Exception.Message)"
  }
  
  try {
    # Single-tenant apps require tenant-specific endpoint (not /common)
    if ($script:UseDeviceCode) {
      Write-Host "Using device code flow for authentication."
      Connect-MgGraph -TenantId $tenantId -ClientId $clientId -Scopes $scopes -UseDeviceCode -NoWelcome -ErrorAction Stop | Out-Null
    } else {
      Connect-MgGraph -TenantId $tenantId -ClientId $clientId -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null
    }
    $ctx = Get-MgContext
    Write-Log "Connected. Tenant=$($ctx.TenantId) Account=$($ctx.Account) ClientId=$($ctx.ClientId)" 'INFO'
    Write-Host ("Connected to Graph. Tenant={0} Account={1} ClientId={2}" -f $ctx.TenantId, $ctx.Account, $ctx.ClientId)
    Write-Log "Permissions: Mode=Delegated Scopes:" 'INFO'
    Write-Host "Using delegated Graph scopes:" 
    foreach ($s in $scopes) {
      Write-Log (" - {0}" -f $s) 'INFO'
      Write-Host (" - {0}" -f $s)
    }
    Write-Log ("Auth summary: Mode=Delegated Tenant={0} ClientId={1} Account={2}" -f $ctx.TenantId, $ctx.ClientId, $ctx.Account) 'INFO'
  } catch {
    Write-Log "Failed to connect to Microsoft Graph. $_" 'ERROR'
    Write-Host "ERROR: Failed to connect to Microsoft Graph. See log for details." -ForegroundColor Red
    throw
  }
}
