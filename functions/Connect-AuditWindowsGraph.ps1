function Connect-AuditWindowsGraph {
  <#
    .SYNOPSIS
    Connects to Microsoft Graph with admin scopes for Audit Windows app provisioning.

    .DESCRIPTION
    Establishes a Microsoft Graph connection with administrative scopes required for
    app registration management (Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All).
    
    If an existing session has the required scopes, it is reused. Otherwise, the function
    initiates interactive authentication. Used by Setup-AuditWindowsApp.ps1 for provisioning.

    .PARAMETER Reauth
    Forces re-authentication even if an existing valid session exists.

    .PARAMETER TenantId
    Target tenant ID. If not specified, uses the default tenant from authentication.

    .OUTPUTS
    Microsoft.Graph.PowerShell.Authentication.AuthContext
    Returns the Graph context object for the authenticated session.

    .EXAMPLE
    $context = Connect-AuditWindowsGraph
    Connects to Graph, reusing existing session if it has required scopes.

    .EXAMPLE
    $context = Connect-AuditWindowsGraph -Reauth
    Forces a fresh authentication, ignoring any existing session.

    .EXAMPLE
    $context = Connect-AuditWindowsGraph -TenantId 'contoso.onmicrosoft.com'
    Connects to a specific tenant.
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

  # Check if we have a valid existing session WITH the required admin scopes
  if ($context -and $context.Account) {
    # Verify the session has the required scopes for app management
    $hasRequiredScopes = $true
    foreach ($requiredScope in $scopes) {
      if ($context.Scopes -notcontains $requiredScope) {
        $hasRequiredScopes = $false
        break
      }
    }
    
    if ($hasRequiredScopes) {
      Write-Host "Using existing Microsoft Graph session as $($context.Account)" -ForegroundColor Green
      return $context
    } else {
      Write-Host "Existing session lacks required admin scopes. Re-authenticating..." -ForegroundColor Yellow
      Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
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
