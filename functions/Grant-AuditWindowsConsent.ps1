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
  
  # Separate application permissions (Role) from delegated permissions (Scope)
  $appPermissions = $ResourceAccess | Where-Object { $_.Type -eq 'Role' }
  $delegatedPermissions = $ResourceAccess | Where-Object { $_.Type -eq 'Scope' }

  # Grant application permissions via AppRoleAssignment
  if ($appPermissions) {
    $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id -All

    foreach ($access in $appPermissions) {
      $alreadyAssigned = $existingAssignments | Where-Object { $_.AppRoleId -eq $access.Id -and $_.ResourceId -eq $GraphServicePrincipal.Id }
      if ($alreadyAssigned) {
        Write-Host " - Application permission $($access.Id) already consented" -ForegroundColor Gray
        continue
      }

      try {
        New-MgServicePrincipalAppRoleAssignment `
          -ServicePrincipalId $ServicePrincipal.Id `
          -PrincipalId $ServicePrincipal.Id `
          -ResourceId $GraphServicePrincipal.Id `
          -AppRoleId $access.Id | Out-Null
        Write-Host " - Granted consent for application permission $($access.Id)" -ForegroundColor Green
      }
      catch {
        throw "Failed to grant admin consent for application permission '$($access.Id)'. Ensure you are a Global Administrator or Privileged Role Administrator. Error: $($_.Exception.Message)"
      }
    }
  }

  # Grant delegated permissions via OAuth2PermissionGrant (admin consent for all users)
  if ($delegatedPermissions) {
    # Build space-separated scope string from permission IDs
    $scopeValues = @()
    foreach ($access in $delegatedPermissions) {
      $scopeDef = $GraphServicePrincipal.Oauth2PermissionScopes | Where-Object { $_.Id -eq $access.Id }
      if ($scopeDef) {
        $scopeValues += $scopeDef.Value
      }
    }

    if ($scopeValues.Count -gt 0) {
      $scopeString = $scopeValues -join ' '
      
      # Check for existing grant
      $existingGrant = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($ServicePrincipal.Id)' and resourceId eq '$($GraphServicePrincipal.Id)'" -ErrorAction SilentlyContinue | Select-Object -First 1

      if ($existingGrant) {
        # Update existing grant to include all scopes
        $existingScopes = if ($existingGrant.Scope) { $existingGrant.Scope -split ' ' } else { @() }
        $allScopes = ($existingScopes + $scopeValues) | Select-Object -Unique
        $newScopeString = $allScopes -join ' '

        if ($newScopeString -ne $existingGrant.Scope) {
          Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $existingGrant.Id -Scope $newScopeString | Out-Null
          Write-Host " - Updated delegated permissions grant: $newScopeString" -ForegroundColor Green
        } else {
          Write-Host " - Delegated permissions already consented: $scopeString" -ForegroundColor Gray
        }
      } else {
        # Create new admin consent grant for all principals
        $grantParams = @{
          ClientId    = $ServicePrincipal.Id
          ConsentType = 'AllPrincipals'
          ResourceId  = $GraphServicePrincipal.Id
          Scope       = $scopeString
        }
        
        try {
          New-MgOauth2PermissionGrant -BodyParameter $grantParams | Out-Null
          Write-Host " - Granted admin consent for delegated permissions: $scopeString" -ForegroundColor Green
        }
        catch {
          throw "Failed to grant admin consent for delegated permissions. Ensure you are a Global Administrator. Error: $($_.Exception.Message)"
        }
      }
    }
  }

  Write-Host 'Admin consent granted successfully.' -ForegroundColor Green
}
