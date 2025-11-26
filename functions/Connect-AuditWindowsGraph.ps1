function Connect-AuditWindowsGraph {
  <#
    .SYNOPSIS
    Connects to Microsoft Graph with admin scopes for Audit Windows app provisioning.
  #>
  param(
    [switch]$Reauth,
    [string]$TenantId
  )

  $scopes = Get-AuditWindowsAdminScopes

  if ($Reauth) {
    try {
      Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
      # Ignore disconnect errors and proceed to re-authenticate
    }
  }

  $context = Get-MgContext

  # Check if we have a valid existing session
  if ($context -and $context.Account) {
    Write-Host "Using existing Microsoft Graph session as $($context.Account)" -ForegroundColor Green
    return $context
  }

  # No existing session - need to authenticate
  Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor Cyan
  Write-Host 'A browser window will open for interactive authentication.' -ForegroundColor Yellow
  Write-Host 'Please sign in with Global Administrator or Application Administrator credentials.' -ForegroundColor Yellow

  try {
    if ($TenantId) {
      Connect-MgGraph -TenantId $TenantId -Scopes $scopes -ErrorAction Stop | Out-Null
    }
    else {
      Connect-MgGraph -Scopes $scopes -ErrorAction Stop | Out-Null
    }
  }
  catch {
    throw "Microsoft Graph authentication failed or was cancelled. Error: $($_.Exception.Message)"
  }

  $context = Get-MgContext
  if (-not $context -or -not $context.Account) {
    throw 'Microsoft Graph authentication failed: no authenticated account found. Re-run the script and complete the authentication process.'
  }

  Write-Host "Successfully authenticated as $($context.Account)" -ForegroundColor Green
  return $context
}
