function Set-AuditWindowsApplication {
  <#
    .SYNOPSIS
    Creates or updates the Audit Windows application registration.
  #>
  param(
    [Parameter(Mandatory)]
    [string]$DisplayName,
    [Parameter(Mandatory)]
    [string]$TenantId
  )

  $app = Get-AuditWindowsApplication -DisplayName $DisplayName

  if (-not $app) {
    Write-Host "Creating Audit Windows application '$DisplayName'..." -ForegroundColor Cyan
    
    # Configure for public client (interactive desktop) authentication
    $publicClient = @{
      RedirectUris = @(
        'http://localhost'
        'https://login.microsoftonline.com/common/oauth2/nativeclient'
      )
    }
    
    $web = @{
      HomePageUrl = 'https://github.com/kkaminsk/auditwindows'
    }
    
    $params = @{
      DisplayName              = $DisplayName
      SignInAudience           = 'AzureADMyOrg'
      IsFallbackPublicClient   = $true
      PublicClient             = $publicClient
      Web                      = $web
    }

    $app = New-MgApplication @params
    Write-Host "Application created with ID: $($app.AppId)" -ForegroundColor Green
  }
  else {
    Write-Host "Found existing application '$DisplayName' (AppId: $($app.AppId))" -ForegroundColor Green
    
    # Ensure public client settings and homepage URL are configured on existing app
    $needsUpdate = $false
    if (-not $app.IsFallbackPublicClient) { $needsUpdate = $true }
    if (-not $app.PublicClient -or -not $app.PublicClient.RedirectUris -or $app.PublicClient.RedirectUris.Count -eq 0) { $needsUpdate = $true }
    if (-not $app.Web -or $app.Web.HomePageUrl -ne 'https://github.com/kkaminsk/auditwindows') { $needsUpdate = $true }
    
    if ($needsUpdate) {
      Write-Host "Updating application settings..." -ForegroundColor Cyan
      $publicClient = @{
        RedirectUris = @(
          'http://localhost'
          'https://login.microsoftonline.com/common/oauth2/nativeclient'
        )
      }
      $web = @{
        HomePageUrl = 'https://github.com/kkaminsk/auditwindows'
      }
      Update-MgApplication -ApplicationId $app.Id -IsFallbackPublicClient:$true -PublicClient $publicClient -Web $web
      Write-Host "Application settings configured." -ForegroundColor Green
    }
  }

  return Get-MgApplication -ApplicationId $app.Id
}
