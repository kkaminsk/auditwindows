function Initialize-AppRegistrationAndConnect {
  <#
    .SYNOPSIS
    Provisions an app registration and connects using certificate authentication.

    .DESCRIPTION
    Handles app-only (certificate-based) authentication for the Windows audit script.
    
    If -Create is specified:
    - Connects with admin scopes to provision the application
    - Creates app registration if it doesn't exist
    - Creates service principal
    - Generates self-signed certificate if not found
    - Attaches certificate to app keyCredentials
    - Grants required Microsoft Graph application permissions
    
    Then connects to Graph using the app's certificate for app-only auth.

    .PARAMETER Tenant
    The tenant ID (GUID or domain) to connect to. Required.

    .PARAMETER Name
    The application registration name. Default: 'WindowsAuditApp'

    .PARAMETER Create
    If specified, provisions the app registration if it doesn't exist.

    .PARAMETER Subject
    The certificate subject name. Default: 'CN={Name}'

    .EXAMPLE
    Initialize-AppRegistrationAndConnect -Tenant 'contoso.onmicrosoft.com' -Create
    Creates app if missing and connects with certificate auth.

    .EXAMPLE
    Initialize-AppRegistrationAndConnect -Tenant $tenantId -Name 'MyAuditApp' -Subject 'CN=MyAuditCert'
    Connects using existing app and certificate.

    .NOTES
    Requires admin privileges (Global Admin or Application Admin) when using -Create.
    Certificate is stored in Cert:\CurrentUser\My.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Tenant,
    [Parameter()][string]$Name = 'WindowsAuditApp',
    [Parameter()][switch]$Create,
    [Parameter()][string]$Subject
  )
  if (-not $Subject -or $Subject.Trim() -eq '') { $Subject = "CN=$Name" }
  Write-Host ("App-based auth requested. TenantId={0} AppName={1}" -f $Tenant, $Name)
  Write-Log ("App-based auth requested. TenantId={0} AppName={1}" -f $Tenant, $Name) 'INFO'

  $app = $null
  $cert = $null
  if ($Create) {
    Write-Host "Connecting (admin) to provision/ensure application (device code)..."
    $adminScopes = 'Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All'
    Connect-MgGraph -UseDeviceCode -Scopes $adminScopes -NoWelcome -ErrorAction Stop | Out-Null
    $ctx = Get-MgContext
    Write-Log ("Admin connected for provisioning. Tenant={0}" -f $ctx.TenantId) 'INFO'

    $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource "GET /applications?`$filter=displayName eq '$Name'" -Script { Get-MgApplication -Filter "displayName eq '$Name'" -All } | Select-Object -First 1
    if (-not $app) {
      Write-Host ("Creating application '{0}'..." -f $Name)
      $app = Invoke-GraphWithRetry -OperationName 'New-MgApplication' -Resource 'POST /applications' -Script { New-MgApplication -DisplayName $Name -SignInAudience 'AzureADMyOrg' }
      Write-Log ("Created application AppId={0} Id={1}" -f $app.AppId, $app.Id) 'INFO'
    } else {
      Write-Host ("Application exists. AppId={0}" -f $app.AppId)
    }

    $sp = Invoke-GraphWithRetry -OperationName 'Get-MgServicePrincipal' -Resource "GET /servicePrincipals?`$filter=appId eq '$($app.AppId)'" -Script { Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -All } | Select-Object -First 1
    if (-not $sp) {
      Write-Host "Creating service principal for the application..."
      $sp = Invoke-GraphWithRetry -OperationName 'New-MgServicePrincipal' -Resource 'POST /servicePrincipals' -Script { New-MgServicePrincipal -AppId $app.AppId }
      Write-Log ("Created service principal Id={0}" -f $sp.Id) 'INFO'
    }

    $cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $Subject } | Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $cert) {
      Write-Host ("Creating self-signed certificate {0}..." -f $Subject)
      $cert = New-SelfSignedCertificate -Subject $Subject -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -NotAfter (Get-Date).AddYears(2)
      Write-Log ("Created certificate Thumbprint={0}" -f $cert.Thumbprint) 'INFO'
    } else {
      Write-Host ("Using existing certificate Thumbprint={0}" -f $cert.Thumbprint)
    }

    # Ensure cert on application keyCredentials (avoid duplicate by thumbprint)
    $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource "GET /applications?`$filter=displayName eq '$Name'" -Script { Get-MgApplication -Filter "displayName eq '$Name'" -All } | Select-Object -First 1
    $thumbBytes = $cert.GetCertHash()
    $thumbB64 = [System.Convert]::ToBase64String($thumbBytes)
    $hasKey = $false
    foreach ($k in ($app.KeyCredentials | ForEach-Object { $_ })) {
      $existingB64 = if ($k.CustomKeyIdentifier) { [System.Convert]::ToBase64String($k.CustomKeyIdentifier) } else { $null }
      if ($existingB64 -eq $thumbB64) { $hasKey = $true; break }
    }
    if (-not $hasKey) {
      Write-Host "Adding certificate to application keyCredentials..."
      $keyObj = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphKeyCredential]::new()
      $keyObj.DisplayName = 'WindowsAuditCert'
      $keyObj.Type = 'AsymmetricX509Cert'
      $keyObj.Usage = 'Verify'
      # Byte[] for Key and CustomKeyIdentifier
      $keyObj.Key = $cert.RawData
      $keyObj.CustomKeyIdentifier = $thumbBytes
      $keyObj.StartDateTime = Get-Date
      $keyObj.EndDateTime = $cert.NotAfter
      $newKeys = @($app.KeyCredentials + $keyObj)
      Invoke-GraphWithRetry -OperationName 'Update-MgApplication' -Resource 'PATCH /applications/{id}' -Script { Update-MgApplication -ApplicationId $app.Id -KeyCredentials $newKeys } | Out-Null
      Write-Log "Certificate added to application." 'INFO'
      $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource 'GET /applications/{id}' -Script { Get-MgApplication -ApplicationId $app.Id }
    }

    # Grant app roles on Microsoft Graph
    $graphSp = Invoke-GraphWithRetry -OperationName 'Get-MgServicePrincipal' -Resource "GET /servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'" -Script { Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -All } | Select-Object -First 1
    $needed = @('Device.Read.All','BitLockerKey.ReadBasic.All','DeviceLocalCredential.ReadBasic.All','DeviceManagementManagedDevices.Read.All')
    $assignments = Invoke-GraphWithRetry -OperationName 'Get-MgServicePrincipalAppRoleAssignment' -Resource 'GET /servicePrincipals/{id}/appRoleAssignments' -Script { Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All }
    foreach ($perm in $needed) {
      $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $perm -and $_.AllowedMemberTypes -contains 'Application' } | Select-Object -First 1
      if ($role) {
        $has = $assignments | Where-Object { $_.AppRoleId -eq $role.Id }
        if (-not $has) {
          Write-Host ("Granting application permission: {0}" -f $perm)
          Invoke-GraphWithRetry -OperationName 'New-MgServicePrincipalAppRoleAssignment' -Resource 'POST /servicePrincipals/{id}/appRoleAssignments' -Script { New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $graphSp.Id -AppRoleId $role.Id } | Out-Null
        }
      } else {
        Write-Log ("App role not found for {0}" -f $perm) 'WARN'
      }
    }
    Write-Host "Provisioning done."
    Disconnect-MgGraph | Out-Null
  } else {
    # No provisioning: find app and cert locally
    if (-not $Subject -or $Subject.Trim() -eq '') { $Subject = "CN=$Name" }
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $Subject } | Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $cert) { throw "Certificate not found in CurrentUser\\My with subject $Subject. Provide -CertSubject or run with -CreateAppIfMissing." }
    Connect-MgGraph -UseDeviceCode -Scopes 'Application.Read.All' -NoWelcome -ErrorAction Stop | Out-Null
    $app = Invoke-GraphWithRetry -OperationName 'Get-MgApplication' -Resource "GET /applications?`$filter=displayName eq '$Name'" -Script { Get-MgApplication -Filter "displayName eq '$Name'" -All } | Select-Object -First 1
    Disconnect-MgGraph | Out-Null
    if (-not $app) { throw "Application '$Name' not found. Use -CreateAppIfMissing to provision." }
  }

  Write-Host "Connecting to Graph with application (certificate)..."
  Connect-MgGraph -TenantId $Tenant -ClientId $app.AppId -CertificateThumbprint $cert.Thumbprint -NoWelcome -ErrorAction Stop | Out-Null
  $ctx2 = Get-MgContext
  Write-Log ("Connected (app-only). Tenant={0} AppId={1} ClientId={2}" -f $ctx2.TenantId, $app.AppId, $ctx2.ClientId) 'INFO'
  Write-Host ("Connected (app-only). Tenant={0} AppId={1} ClientId={2}" -f $ctx2.TenantId, $app.AppId, $ctx2.ClientId)
  Write-Log "Permissions: Mode=AppOnly AppRoles:" 'INFO'
  Write-Host "Using app-only Graph application permissions:" 
  foreach ($p in $needed) {
    Write-Log (" - {0}" -f $p) 'INFO'
    Write-Host (" - {0}" -f $p)
  }
  Write-Log ("Auth summary: Mode=AppOnly Tenant={0} AppId={1} ClientId={2} AppName={3}" -f $ctx2.TenantId, $app.AppId, $ctx2.ClientId, $Name) 'INFO'
}
