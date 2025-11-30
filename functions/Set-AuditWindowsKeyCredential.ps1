function Set-AuditWindowsKeyCredential {
  <#
    .SYNOPSIS
    Adds a certificate credential to the Audit Windows application.
    .DESCRIPTION
    Creates or uses an existing certificate for app-only authentication. Supports both exportable
    and non-exportable certificates. Non-exportable certificates provide stronger security by
    preventing private key extraction, but cannot be backed up or migrated.
    .PARAMETER Application
    The application object to attach the certificate to.
    .PARAMETER CertificateSubject
    Subject name for the certificate. Default: 'CN=AuditWindowsCert'
    .PARAMETER CertificateValidityInMonths
    Validity period for generated certificates (1-60 months). Default: 24
    .PARAMETER ExistingCertificateThumbprint
    Thumbprint of an existing certificate to use instead of generating a new one.
    .PARAMETER SkipExport
    Skip exporting the certificate to .cer and .pfx files.
    .PARAMETER NonExportable
    Create the certificate with KeyExportPolicy NonExportable. This prevents the private key from
    being exported, providing stronger protection against credential theft. Trade-off: the
    certificate cannot be backed up or migrated. If lost, regenerate using this script.
    .OUTPUTS
    Returns the certificate object.
  #>
  param(
    [Parameter(Mandatory)]
    $Application,
    [string]$CertificateSubject = 'CN=AuditWindowsCert',
    [int]$CertificateValidityInMonths = 24,
    [string]$ExistingCertificateThumbprint,
    [switch]$SkipExport,
    [switch]$NonExportable
  )

  $certificate = $null

  if ($ExistingCertificateThumbprint) {
    # Use existing certificate from store
    $normalizedThumbprint = ConvertTo-AuditWindowsThumbprintString -Thumbprint $ExistingCertificateThumbprint
    $certificate = Get-ChildItem -Path 'Cert:\CurrentUser\My' | Where-Object { $_.Thumbprint -eq $normalizedThumbprint } | Select-Object -First 1

    if (-not $certificate) {
      throw "Certificate with thumbprint '$ExistingCertificateThumbprint' not found in Cert:\CurrentUser\My."
    }

    Write-Host "Using existing certificate: $($certificate.Subject) (Thumbprint: $($certificate.Thumbprint))" -ForegroundColor Cyan
  }
  else {
    # Generate new self-signed certificate
    $exportPolicy = if ($NonExportable) { 'NonExportable' } else { 'Exportable' }
    Write-Host "Generating new self-signed certificate with subject '$CertificateSubject' (KeyExportPolicy: $exportPolicy)..." -ForegroundColor Cyan
    $notAfter = (Get-Date).AddMonths($CertificateValidityInMonths)

    $certificate = New-SelfSignedCertificate `
      -Subject $CertificateSubject `
      -CertStoreLocation 'Cert:\CurrentUser\My' `
      -KeyExportPolicy $exportPolicy `
      -KeySpec Signature `
      -KeyLength 2048 `
      -KeyAlgorithm RSA `
      -HashAlgorithm SHA256 `
      -NotAfter $notAfter `
      -ErrorAction Stop

    Write-Host "Certificate generated: $($certificate.Subject) (Thumbprint: $($certificate.Thumbprint), Expires: $notAfter)" -ForegroundColor Green

    if ($NonExportable) {
      # Non-exportable certificates cannot be backed up - skip export prompts entirely
      Write-Host "Certificate created with non-exportable private key (cannot be backed up or migrated)." -ForegroundColor Yellow
      Write-Host "If this certificate is lost, run this script again to generate a new one." -ForegroundColor Gray
    }
    elseif (-not $SkipExport) {
      # Export certificate artifacts (optional) - only for exportable certificates
      $skipBackup = Read-Host -Prompt 'Skip certificate file backup? (y/N)'
      if ($skipBackup -eq 'y' -or $skipBackup -eq 'Y') {
        Write-Host "Certificate file export skipped (stored in Cert:\CurrentUser\My)." -ForegroundColor Yellow
      }
      else {
        $paths = Get-AuditWindowsCertificateArtifactPaths -BaseName ($CertificateSubject -replace '^CN=', '')

        # Export .cer (public key only)
        Export-Certificate -Cert $certificate -FilePath $paths.Cer -Type CERT | Out-Null
        Write-Host "Public certificate exported to: $($paths.Cer)" -ForegroundColor Green

        # Export .pfx (with private key)
        $pfxPassword = Read-Host -Prompt 'Enter password for PFX export' -AsSecureString
        Export-PfxCertificate -Cert $certificate -FilePath $paths.Pfx -Password $pfxPassword | Out-Null
        Write-Host "Private certificate exported to: $($paths.Pfx)" -ForegroundColor Green
      }
    } else {
      Write-Host "Certificate file export skipped (stored in Cert:\CurrentUser\My)." -ForegroundColor Yellow
    }
  }

  # Check if certificate is already attached to the app
  $existingKey = Find-AuditWindowsKeyCredential -KeyCredentials $Application.KeyCredentials -Thumbprint $certificate.Thumbprint
  if ($existingKey) {
    Write-Host 'Certificate is already attached to the application.' -ForegroundColor Green
    return $certificate
  }

  # Add certificate to application
  Write-Host 'Attaching certificate to application...' -ForegroundColor Cyan

  $keyCredential = @{
    Type             = 'AsymmetricX509Cert'
    Usage            = 'Verify'
    Key              = $certificate.RawData
    DisplayName      = "AuditWindows-$($certificate.Thumbprint)"
    StartDateTime    = $certificate.NotBefore
    EndDateTime      = $certificate.NotAfter
  }

  try {
    # Note: We cannot preserve existing key credentials because Microsoft Graph doesn't return
    # the Key (certificate data) property for security reasons. Setting new credentials will
    # replace any existing ones. This is expected behavior for a setup script.
    if ($Application.KeyCredentials -and $Application.KeyCredentials.Count -gt 0) {
      Write-Host "Note: Replacing $($Application.KeyCredentials.Count) existing certificate(s) with new certificate." -ForegroundColor Yellow
    }

    Update-MgApplication -ApplicationId $Application.Id -KeyCredentials @($keyCredential) -ErrorAction Stop | Out-Null
    Write-Host 'Certificate attached successfully.' -ForegroundColor Green
  }
  catch {
    throw "Failed to attach certificate to application. Error: $($_.Exception.Message)"
  }

  return $certificate
}
