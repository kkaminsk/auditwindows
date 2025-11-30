function Test-AuditWindowsCertificateHealth {
  <#
    .SYNOPSIS
    Checks the health and expiration status of the Audit Windows certificate.
    .DESCRIPTION
    Evaluates the certificate used for app-only authentication, checking expiration status
    and providing warnings for certificates approaching expiration. Returns a structured
    object with health status, days until expiry, and actionable messages.
    .PARAMETER CertificateSubject
    Subject name to search for in Cert:\CurrentUser\My. Default: 'CN=AuditWindowsCert'
    .PARAMETER CertificateThumbprint
    Specific certificate thumbprint to check. Takes precedence over CertificateSubject.
    .PARAMETER WarningDaysBeforeExpiry
    Number of days before expiry to trigger a warning. Default: 30
    .OUTPUTS
    PSCustomObject with properties:
      - Healthy: Boolean indicating if certificate is valid and not expiring soon
      - DaysUntilExpiry: Integer days until certificate expires (negative if expired)
      - Certificate: The certificate object (or $null if not found)
      - Message: Human-readable status message
    .EXAMPLE
    Test-AuditWindowsCertificateHealth
    Checks the default AuditWindowsCert for expiration.
    .EXAMPLE
    Test-AuditWindowsCertificateHealth -WarningDaysBeforeExpiry 60
    Uses a 60-day warning threshold instead of the default 30 days.
    .EXAMPLE
    Test-AuditWindowsCertificateHealth -CertificateThumbprint 'ABC123...'
    Checks a specific certificate by thumbprint.
  #>
  [CmdletBinding()]
  param(
    [string]$CertificateSubject = 'CN=AuditWindowsCert',
    [string]$CertificateThumbprint,
    [int]$WarningDaysBeforeExpiry = 30
  )

  $certificate = $null

  if ($CertificateThumbprint) {
    # Normalize thumbprint (remove spaces, convert to uppercase)
    $normalizedThumbprint = $CertificateThumbprint -replace '\s', '' -replace ':', ''
    $normalizedThumbprint = $normalizedThumbprint.ToUpperInvariant()
    $certificate = Get-ChildItem -Path 'Cert:\CurrentUser\My' |
      Where-Object { $_.Thumbprint -eq $normalizedThumbprint } |
      Select-Object -First 1
  }
  else {
    # Find by subject, prefer newest if multiple exist
    $certificate = Get-ChildItem -Path 'Cert:\CurrentUser\My' |
      Where-Object { $_.Subject -eq $CertificateSubject } |
      Sort-Object NotAfter -Descending |
      Select-Object -First 1
  }

  # Certificate not found
  if (-not $certificate) {
    $searchCriteria = if ($CertificateThumbprint) { "thumbprint '$CertificateThumbprint'" } else { "subject '$CertificateSubject'" }
    return [PSCustomObject]@{
      Healthy         = $false
      DaysUntilExpiry = $null
      Certificate     = $null
      Message         = "Certificate not found with $searchCriteria in Cert:\CurrentUser\My"
    }
  }

  # Calculate days until expiry
  $now = Get-Date
  $daysUntilExpiry = [int]($certificate.NotAfter - $now).TotalDays

  # Determine health status and message
  if ($daysUntilExpiry -lt 0) {
    # Expired
    return [PSCustomObject]@{
      Healthy         = $false
      DaysUntilExpiry = $daysUntilExpiry
      Certificate     = $certificate
      Message         = "Certificate EXPIRED $([Math]::Abs($daysUntilExpiry)) days ago (expired $($certificate.NotAfter.ToString('yyyy-MM-dd'))). Regenerate using Setup-AuditWindowsApp.ps1."
    }
  }
  elseif ($daysUntilExpiry -le $WarningDaysBeforeExpiry) {
    # Expiring soon
    return [PSCustomObject]@{
      Healthy         = $false
      DaysUntilExpiry = $daysUntilExpiry
      Certificate     = $certificate
      Message         = "Certificate expires in $daysUntilExpiry days ($($certificate.NotAfter.ToString('yyyy-MM-dd'))). Consider regenerating soon using Setup-AuditWindowsApp.ps1."
    }
  }
  else {
    # Healthy
    return [PSCustomObject]@{
      Healthy         = $true
      DaysUntilExpiry = $daysUntilExpiry
      Certificate     = $certificate
      Message         = "Certificate is healthy. Expires in $daysUntilExpiry days ($($certificate.NotAfter.ToString('yyyy-MM-dd')))."
    }
  }
}
