function Set-AuditWindowsKeyCredential {
  <#
    .SYNOPSIS
    Adds a certificate credential to the Audit Windows application.
    .OUTPUTS
    Returns the certificate object.
  #>
  param(
    [Parameter(Mandatory)]
    $Application,
    [string]$CertificateSubject = 'CN=AuditWindowsCert',
    [int]$CertificateValidityInMonths = 24,
    [string]$ExistingCertificateThumbprint
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
    Write-Host "Generating new self-signed certificate with subject '$CertificateSubject'..." -ForegroundColor Cyan
    $notAfter = (Get-Date).AddMonths($CertificateValidityInMonths)

    $certificate = New-SelfSignedCertificate `
      -Subject $CertificateSubject `
      -CertStoreLocation 'Cert:\CurrentUser\My' `
      -KeyExportPolicy Exportable `
      -KeySpec Signature `
      -KeyLength 2048 `
      -KeyAlgorithm RSA `
      -HashAlgorithm SHA256 `
      -NotAfter $notAfter `
      -ErrorAction Stop

    Write-Host "Certificate generated: $($certificate.Subject) (Thumbprint: $($certificate.Thumbprint), Expires: $notAfter)" -ForegroundColor Green

    # Export certificate artifacts
    $paths = Get-AuditWindowsCertificateArtifactPaths -BaseName ($CertificateSubject -replace '^CN=', '')
    
    # Export .cer (public key only)
    Export-Certificate -Cert $certificate -FilePath $paths.Cer -Type CERT | Out-Null
    Write-Host "Public certificate exported to: $($paths.Cer)" -ForegroundColor Green

    # Export .pfx (with private key, requires password)
    $pfxPassword = Read-Host -Prompt 'Enter password for PFX export (or press Enter for no password)' -AsSecureString
    if ($pfxPassword.Length -gt 0) {
      Export-PfxCertificate -Cert $certificate -FilePath $paths.Pfx -Password $pfxPassword | Out-Null
    }
    else {
      # PowerShell 7 allows export without password
      Export-PfxCertificate -Cert $certificate -FilePath $paths.Pfx -NoPassword | Out-Null
    }
    Write-Host "Private certificate exported to: $($paths.Pfx)" -ForegroundColor Green
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
    # Get existing key credentials and add the new one
    $existingKeys = @($Application.KeyCredentials | ForEach-Object {
      @{
        Type          = $_.Type
        Usage         = $_.Usage
        Key           = $_.Key
        DisplayName   = $_.DisplayName
        StartDateTime = $_.StartDateTime
        EndDateTime   = $_.EndDateTime
        KeyId         = $_.KeyId
      }
    })
    $allKeys = $existingKeys + @($keyCredential)

    Update-MgApplication -ApplicationId $Application.Id -KeyCredentials $allKeys -ErrorAction Stop | Out-Null
    Write-Host 'Certificate attached successfully.' -ForegroundColor Green
  }
  catch {
    throw "Failed to attach certificate to application. Error: $($_.Exception.Message)"
  }

  return $certificate
}
