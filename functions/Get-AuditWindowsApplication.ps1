function Get-AuditWindowsApplication {
  <#
    .SYNOPSIS
    Retrieves an existing Audit Windows application by display name.
  #>
  param(
    [Parameter(Mandatory)]
    [string]$DisplayName
  )

  return Get-MgApplication -Filter "displayName eq '$DisplayName'" -ErrorAction SilentlyContinue | Select-Object -First 1
}
