function Get-AuditWindowsApplication {
  <#
    .SYNOPSIS
    Retrieves an existing Audit Windows application by display name.
  #>
  param(
    [Parameter(Mandatory)]
    [string]$DisplayName
  )

  $safeName = Protect-ODataFilterValue $DisplayName
  return Get-MgApplication -Filter "displayName eq '$safeName'" -ErrorAction SilentlyContinue | Select-Object -First 1
}
