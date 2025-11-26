function Connect-GraphInteractive {
  $scopes = 'Device.Read.All','BitLockerKey.ReadBasic.All','DeviceLocalCredential.ReadBasic.All','DeviceManagementManagedDevices.Read.All'
  Write-Log "Connecting to Graph with scopes: $($scopes -join ', ')"
  Write-Host "Connecting to Microsoft Graph..."
  
  # Search for and select a custom application
  $appName = if ($script:AppDisplayName) { $script:AppDisplayName } else { 'Audit Windows' }
  Write-Host "Searching for available enterprise applications..." -ForegroundColor Cyan
  Write-Log "Searching for available enterprise applications (service principals)" 'INFO'
  
  $clientId = $null
  $tenantId = $script:TenantId  # Use provided TenantId if available
  try {
    # First connect without scopes to query apps (user must have read access)
    Connect-MgGraph -Scopes 'Application.Read.All' -NoWelcome -ErrorAction Stop | Out-Null
    $lookupCtx = Get-MgContext
    if (-not $tenantId -and $lookupCtx.TenantId) {
      $tenantId = $lookupCtx.TenantId  # Capture tenant from lookup session
    }
    
    # Search for service principals (enterprise apps) - these are apps users can actually authenticate with
    # First try exact match by display name
    $dedicatedApp = Get-MgServicePrincipal -Filter "displayName eq '$appName' and servicePrincipalType eq 'Application'" -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if (-not $dedicatedApp) {
      # App not found - run Setup-AuditWindowsApp.ps1 to create it
      Write-Host ""
      Write-Host "Application '$appName' not found. Running setup to create it..." -ForegroundColor Yellow
      Write-Log "Dedicated app '$appName' not found, invoking Setup-AuditWindowsApp.ps1" 'INFO'
      
      Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
      
      # Locate and run the setup script
      $setupScript = Join-Path -Path $PSScriptRoot -ChildPath '..\Setup-AuditWindowsApp.ps1'
      if (-not (Test-Path -Path $setupScript)) {
        $setupScript = Join-Path -Path $PSScriptRoot -ChildPath 'Setup-AuditWindowsApp.ps1'
      }
      if (-not (Test-Path -Path $setupScript)) {
        # Try from script root of main script
        $setupScript = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Setup-AuditWindowsApp.ps1'
      }
      
      if (-not (Test-Path -Path $setupScript)) {
        Write-Host "ERROR: Setup-AuditWindowsApp.ps1 not found." -ForegroundColor Red
        Write-Log "Setup script not found at expected locations" 'ERROR'
        throw "Setup-AuditWindowsApp.ps1 not found. Please run it manually to create the '$appName' application."
      }
      
      Write-Host ""
      Write-Host "Launching Setup-AuditWindowsApp.ps1..." -ForegroundColor Cyan
      Write-Log "Invoking setup script: $setupScript" 'INFO'
      
      # Run the setup script with the app name
      $setupParams = @{
        AppDisplayName = $appName
      }
      if ($tenantId) {
        $setupParams['TenantId'] = $tenantId
      }
      
      & $setupScript @setupParams
      
      Write-Host ""
      Write-Host "Setup complete. Reconnecting to find the new application..." -ForegroundColor Cyan
      Write-Log "Setup script completed, reconnecting to verify app creation" 'INFO'
      
      # Reconnect and find the newly created app
      Connect-MgGraph -Scopes 'Application.Read.All' -NoWelcome -ErrorAction Stop | Out-Null
      $dedicatedApp = Get-MgServicePrincipal -Filter "displayName eq '$appName' and servicePrincipalType eq 'Application'" -ErrorAction SilentlyContinue | Select-Object -First 1
      
      if (-not $dedicatedApp) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Host "ERROR: Application '$appName' still not found after setup." -ForegroundColor Red
        Write-Log "App '$appName' not found after running setup script" 'ERROR'
        throw "Application '$appName' was not created successfully. Check the setup script output for errors."
      }
      
      Write-Host "Application '$appName' created successfully." -ForegroundColor Green
      Write-Log "App '$appName' found after setup" 'INFO'
    }
    
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    
    $clientId = $dedicatedApp.AppId
    Write-Host "Using app: $($dedicatedApp.DisplayName) (ClientId: $clientId)" -ForegroundColor Green
    Write-Log "Using app ClientId=$clientId TenantId=$tenantId" 'INFO'
  } catch {
    if ($_.Exception.Message -match 'not found|No applications') { throw }
    Write-Log "Failed to look up applications: $($_.Exception.Message)" 'ERROR'
    throw "Failed to look up applications: $($_.Exception.Message)"
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
