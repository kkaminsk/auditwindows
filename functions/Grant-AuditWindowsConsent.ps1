function Grant-AuditWindowsConsent {
  <#
    .SYNOPSIS
    Grants admin consent for Microsoft Graph permissions to the Audit Windows service principal.
  #>
  param(
    [Parameter(Mandatory)]
    $ServicePrincipal,
    [Parameter(Mandatory)]
    $GraphServicePrincipal,
    [Parameter(Mandatory)]
    $ResourceAccess
  )

  Write-Host 'Granting admin consent for Microsoft Graph permissions...' -ForegroundColor Cyan
  $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id -All

  foreach ($access in $ResourceAccess) {
    $alreadyAssigned = $existingAssignments | Where-Object { $_.AppRoleId -eq $access.Id -and $_.ResourceId -eq $GraphServicePrincipal.Id }
    if ($alreadyAssigned) {
      Write-Host " - Permission $($access.Id) already consented" -ForegroundColor Gray
      continue
    }

    try {
      New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $ServicePrincipal.Id `
        -PrincipalId $ServicePrincipal.Id `
        -ResourceId $GraphServicePrincipal.Id `
        -AppRoleId $access.Id | Out-Null
      Write-Host " - Granted consent for permission $($access.Id)" -ForegroundColor Green
    }
    catch {
      throw "Failed to grant admin consent for permission '$($access.Id)'. Ensure you are a Global Administrator or Privileged Role Administrator. Error: $($_.Exception.Message)"
    }
  }

  Write-Host 'Admin consent granted successfully.' -ForegroundColor Green
}
