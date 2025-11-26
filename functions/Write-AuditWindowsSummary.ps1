function Write-AuditWindowsSummary {
  <#
    .SYNOPSIS
    Outputs the provisioning summary to console and optionally to a JSON file.

    .DESCRIPTION
    Displays the Audit Windows app registration details (Application ID, Tenant ID,
    certificate thumbprint, logo status) to the console. Optionally exports the summary
    to a JSON file and opens the Entra Portal to the app's overview page.

    .PARAMETER Summary
    A PSObject containing the provisioning summary with properties: ApplicationId, TenantId,
    CertificateThumbprint, CertificateExpiresOn, LogoUploaded.

    .PARAMETER SkipFileExport
    If specified, skips exporting the summary to a JSON file.

    .PARAMETER OutputPath
    Custom path for the summary JSON file. Defaults to %USERPROFILE%\AuditWindowsAppSummary.json.

    .EXAMPLE
    Write-AuditWindowsSummary -Summary $summary
    Displays summary, exports to default JSON path, and opens Entra Portal.

    .EXAMPLE
    Write-AuditWindowsSummary -Summary $summary -SkipFileExport
    Displays summary and opens Entra Portal without exporting JSON.
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

  # Open Entra Portal to the app's overview page
  $portalUrl = "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$($Summary.ApplicationId)/isMSAApp~/false"
  Write-Host "`nOpening Entra Portal to the Audit Windows app overview... (A browser window should appear)" -ForegroundColor Yellow
  try {
    Start-Process $portalUrl -ErrorAction Stop
  }
  catch {
    Write-Host 'Unable to automatically open the browser. Use the following URL:' -ForegroundColor Yellow
    Write-Host $portalUrl -ForegroundColor Yellow
  }
}
