# AuditWindows Automation Shared Helpers
# Provides reusable functions for Audit Windows app provisioning.

function Get-AuditWindowsPermissionNames {
  <#
    .SYNOPSIS
    Returns the Microsoft Graph application permissions required by Audit Windows.
  #>
  return @(
    'Device.Read.All',
    'BitLockerKey.ReadBasic.All',
    'DeviceLocalCredential.ReadBasic.All',
    'DeviceManagementManagedDevices.Read.All'
  )
}

function Get-AuditWindowsAdminScopes {
  <#
    .SYNOPSIS
    Returns the delegated scopes required for admin provisioning.
  #>
  return @(
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All'
  )
}

function ConvertTo-AuditWindowsThumbprintString {
  <#
    .SYNOPSIS
    Normalizes a thumbprint by stripping non-hex characters and uppercasing.
  #>
  param(
    [Parameter(Mandatory)] [string] $Thumbprint
  )
  return (($Thumbprint -replace '[^A-Fa-f0-9]', '').ToUpper())
}

function Get-AuditWindowsThumbprintFromKeyCredential {
  <#
    .SYNOPSIS
    Extracts a thumbprint string from a key credential's CustomKeyIdentifier or DisplayName.
  #>
  param(
    [Parameter(Mandatory)] [psobject] $KeyCredential
  )

  if ($KeyCredential.CustomKeyIdentifier) {
    $bytes = $KeyCredential.CustomKeyIdentifier
    if ($bytes -is [string]) {
      $bytes = [System.Convert]::FromBase64String($bytes)
    }
    if ($bytes -is [byte[]]) {
      return ([System.BitConverter]::ToString($bytes)).Replace('-', '')
    }
  }

  if ($KeyCredential.DisplayName -and $KeyCredential.DisplayName -match '([A-Fa-f0-9]{16,})$') {
    return $Matches[1].ToUpper()
  }

  return $null
}

function Find-AuditWindowsKeyCredential {
  <#
    .SYNOPSIS
    Searches key credentials for a matching thumbprint.
  #>
  param(
    [Parameter()] [psobject[]] $KeyCredentials,
    [Parameter(Mandatory)] [string] $Thumbprint
  )

  if (-not $KeyCredentials -or $KeyCredentials.Count -eq 0) {
    return $null
  }

  $target = ConvertTo-AuditWindowsThumbprintString -Thumbprint $Thumbprint
  foreach ($credential in $KeyCredentials) {
    $candidate = Get-AuditWindowsThumbprintFromKeyCredential -KeyCredential $credential
    if ($candidate -and $candidate -eq $target) {
      return $credential
    }
  }

  return $null
}

function Get-AuditWindowsCertificateArtifactPaths {
  <#
    .SYNOPSIS
    Builds default CER and PFX export paths under the current user's profile.
  #>
  param(
    [Parameter()] [string] $BaseName = 'AuditWindowsCert',
    [Parameter()] [string] $Directory = $env:USERPROFILE
  )

  if (-not $Directory) {
    throw 'Unable to determine user profile directory for certificate export.'
  }

  $sanitizedBase = ($BaseName -replace '[^a-zA-Z0-9_-]', '')
  if (-not $sanitizedBase) {
    $sanitizedBase = 'AuditWindowsCert'
  }

  [pscustomobject]@{
    Cer = Join-Path -Path $Directory -ChildPath "$sanitizedBase.cer"
    Pfx = Join-Path -Path $Directory -ChildPath "$sanitizedBase.pfx"
  }
}

function New-AuditWindowsSummaryRecord {
  <#
    .SYNOPSIS
    Creates a structured object for provisioning output.
  #>
  param(
    [Parameter(Mandatory)] [string] $AppId,
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $CertificateThumbprint,
    [Parameter(Mandatory)] [datetime] $CertificateExpiration,
    [Parameter()] [bool] $LogoUploaded = $false
  )

  [pscustomobject]@{
    Timestamp             = Get-Date
    ApplicationId         = $AppId
    TenantId              = $TenantId
    CertificateThumbprint = $CertificateThumbprint
    CertificateExpiresOn  = $CertificateExpiration
    LogoUploaded          = $LogoUploaded
  }
}

function Get-AuditWindowsGraphResourceAccess {
  <#
    .SYNOPSIS
    Builds the RequiredResourceAccess structure for Microsoft Graph based on a service principal's app roles and delegated scopes.
  #>
  param(
    [Parameter(Mandatory)] $ServicePrincipal,
    [Parameter()] [string[]] $PermissionNames = (Get-AuditWindowsPermissionNames)
  )

  if (-not $ServicePrincipal.AppId) {
    throw 'Service principal object is missing AppId.'
  }

  if (-not $ServicePrincipal.AppRoles) {
    throw 'Service principal object is missing AppRoles collection.'
  }

  $resourceAccess = @()
  foreach ($permission in $PermissionNames | Select-Object -Unique) {
    # Add application permission (Role) for app-only auth
    $role = $ServicePrincipal.AppRoles | Where-Object {
      $_.Value -eq $permission -and $_.AllowedMemberTypes -contains 'Application'
    }

    if ($role) {
      $resourceAccess += @{
        Id   = $role.Id
        Type = 'Role'
      }
    } else {
      Write-Warning "Application permission '$permission' not found on service principal $($ServicePrincipal.AppId)."
    }

    # Add delegated permission (Scope) for interactive auth
    $scope = $ServicePrincipal.Oauth2PermissionScopes | Where-Object {
      $_.Value -eq $permission
    }

    if ($scope) {
      $resourceAccess += @{
        Id   = $scope.Id
        Type = 'Scope'
      }
    } else {
      Write-Warning "Delegated permission '$permission' not found on service principal $($ServicePrincipal.AppId)."
    }
  }

  if (-not $resourceAccess) {
    return @()
  }

  return ,(@{
    ResourceAppId  = $ServicePrincipal.AppId
    ResourceAccess = $resourceAccess
  })
}

Export-ModuleMember -Function `
  Get-AuditWindowsPermissionNames,
  Get-AuditWindowsAdminScopes,
  Get-AuditWindowsCertificateArtifactPaths,
  New-AuditWindowsSummaryRecord,
  Get-AuditWindowsGraphResourceAccess,
  ConvertTo-AuditWindowsThumbprintString,
  Get-AuditWindowsThumbprintFromKeyCredential,
  Find-AuditWindowsKeyCredential
