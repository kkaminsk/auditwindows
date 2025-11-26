function Write-AuditWindowsSummary {
  <#
    .SYNOPSIS
    Outputs the provisioning summary to console and optionally to a JSON file.
  #>
  param(
    [Parameter(Mandatory)]
    [psobject]$Summary,
    [switch]$SkipFileExport,
    [string]$OutputPath
  )

  Write-Host "`nAudit Windows provisioning complete." -ForegroundColor Green
  Write-Host "Application (client) ID: $($Summary.ApplicationId)" -ForegroundColor Green
  Write-Host "Directory (tenant) ID:   $($Summary.TenantId)" -ForegroundColor Green
  Write-Host "Certificate thumbprint:  $($Summary.CertificateThumbprint) (expires $($Summary.CertificateExpiresOn))" -ForegroundColor Green
  Write-Host "Logo uploaded:           $($Summary.LogoUploaded)" -ForegroundColor Green

  if (-not $SkipFileExport) {
    if (-not $OutputPath) {
      $OutputPath = Join-Path -Path $env:USERPROFILE -ChildPath 'AuditWindowsAppSummary.json'
    }

    $Summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "`nSummary exported to: $OutputPath" -ForegroundColor Cyan
  }

  # Open Entra Portal to the app's credentials blade
  $portalUrl = "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/$($Summary.ApplicationId)/isMSAApp~/false"
  Write-Host "`nOpening Entra Portal to the Audit Windows app credentials blade..." -ForegroundColor Cyan
  try {
    Start-Process $portalUrl -ErrorAction Stop
  }
  catch {
    Write-Host 'Unable to automatically open the browser. Use the following URL:' -ForegroundColor Yellow
    Write-Host $portalUrl -ForegroundColor Yellow
  }
}
