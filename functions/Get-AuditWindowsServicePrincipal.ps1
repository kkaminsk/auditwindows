function Get-AuditWindowsServicePrincipal {
  <#
    .SYNOPSIS
    Retrieves or creates the service principal for an Audit Windows application.
  #>
  param(
    [Parameter(Mandatory)]
    [string]$AppId
  )

  $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction SilentlyContinue | Select-Object -First 1

  if (-not $sp) {
    Write-Host "Creating service principal for application $AppId..." -ForegroundColor Cyan
    $sp = New-MgServicePrincipal -AppId $AppId -ErrorAction Stop
  }

  return $sp
}
