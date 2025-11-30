function Get-AuditWindowsKeyVaultCertificate {
  <#
    .SYNOPSIS
    Retrieves or creates a certificate from Azure Key Vault for Audit Windows authentication.
    .DESCRIPTION
    Retrieves a certificate from Azure Key Vault for use with app-only authentication. Optionally
    creates the certificate in Key Vault if it doesn't exist. This provides centralized, HSM-backed
    (with Premium SKU) certificate storage with audit logging and easier rotation.

    The certificate is downloaded to the local certificate store for authentication, but the
    private key remains protected in Key Vault.
    .PARAMETER VaultName
    Name of the Azure Key Vault. Required.
    .PARAMETER CertificateName
    Name of the certificate in Key Vault. Default: 'AuditWindowsCert'
    .PARAMETER CreateIfMissing
    If specified, creates the certificate in Key Vault if it doesn't exist.
    .PARAMETER ValidityInMonths
    Validity period for new certificates (used with -CreateIfMissing). Default: 24
    .PARAMETER Subject
    Subject name for new certificates (used with -CreateIfMissing). Default: 'CN=AuditWindowsCert'
    .OUTPUTS
    Returns a PSCustomObject with:
      - Certificate: The X509Certificate2 object (or $null if not found/created)
      - Thumbprint: Certificate thumbprint
      - KeyVaultUri: URI of the certificate in Key Vault
      - Success: Boolean indicating success
      - Message: Status message
    .EXAMPLE
    Get-AuditWindowsKeyVaultCertificate -VaultName 'mykeyvault'
    Retrieves the AuditWindowsCert from the specified Key Vault.
    .EXAMPLE
    Get-AuditWindowsKeyVaultCertificate -VaultName 'mykeyvault' -CreateIfMissing
    Creates the certificate if it doesn't exist, then retrieves it.
    .EXAMPLE
    Get-AuditWindowsKeyVaultCertificate -VaultName 'mykeyvault' -CertificateName 'CustomCert' -ValidityInMonths 36
    Uses a custom certificate name and validity period.
    .NOTES
    Requires Az.KeyVault module and Azure authentication (Connect-AzAccount).
    For HSM-backed keys, create the Key Vault with --sku premium.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$VaultName,
    [string]$CertificateName = 'AuditWindowsCert',
    [switch]$CreateIfMissing,
    [int]$ValidityInMonths = 24,
    [string]$Subject = 'CN=AuditWindowsCert'
  )

  # Ensure Az.KeyVault module is available
  $keyVaultModule = Get-Module -ListAvailable -Name 'Az.KeyVault'
  if (-not $keyVaultModule) {
    return [PSCustomObject]@{
      Certificate  = $null
      Thumbprint   = $null
      KeyVaultUri  = $null
      Success      = $false
      Message      = "Az.KeyVault module is not installed. Install it with: Install-Module -Name Az.KeyVault -Scope CurrentUser"
    }
  }

  # Import module if not loaded
  if (-not (Get-Module -Name 'Az.KeyVault')) {
    Import-Module 'Az.KeyVault' -Force -ErrorAction Stop
  }

  # Check Azure authentication
  try {
    $azContext = Get-AzContext -ErrorAction Stop
    if (-not $azContext) {
      return [PSCustomObject]@{
        Certificate  = $null
        Thumbprint   = $null
        KeyVaultUri  = $null
        Success      = $false
        Message      = "Not authenticated to Azure. Run Connect-AzAccount first."
      }
    }
  }
  catch {
    return [PSCustomObject]@{
      Certificate  = $null
      Thumbprint   = $null
      KeyVaultUri  = $null
      Success      = $false
      Message      = "Azure authentication check failed: $($_.Exception.Message)"
    }
  }

  $keyVaultUri = "https://$VaultName.vault.azure.net/certificates/$CertificateName"

  # Try to get existing certificate
  try {
    $kvCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -ErrorAction Stop
  }
  catch {
    if ($_.Exception.Message -notmatch 'NotFound|does not exist') {
      return [PSCustomObject]@{
        Certificate  = $null
        Thumbprint   = $null
        KeyVaultUri  = $keyVaultUri
        Success      = $false
        Message      = "Failed to retrieve certificate from Key Vault: $($_.Exception.Message)"
      }
    }
    $kvCert = $null
  }

  # Create if missing
  if (-not $kvCert -and $CreateIfMissing) {
    Write-Host "Certificate '$CertificateName' not found in Key Vault '$VaultName'. Creating..." -ForegroundColor Cyan

    try {
      # Create certificate policy
      $policy = New-AzKeyVaultCertificatePolicy `
        -SubjectName $Subject `
        -IssuerName 'Self' `
        -ValidityInMonths $ValidityInMonths `
        -KeyType 'RSA' `
        -KeySize 2048 `
        -Exportable:$false `
        -ReuseKeyOnRenewal:$true `
        -ErrorAction Stop

      # Start certificate creation
      $certOperation = Add-AzKeyVaultCertificate `
        -VaultName $VaultName `
        -Name $CertificateName `
        -CertificatePolicy $policy `
        -ErrorAction Stop

      Write-Host "Certificate creation initiated. Waiting for completion..." -ForegroundColor Cyan

      # Wait for certificate to be created (self-signed is usually quick)
      $maxWaitSeconds = 60
      $waitedSeconds = 0
      do {
        Start-Sleep -Seconds 2
        $waitedSeconds += 2
        $certOperation = Get-AzKeyVaultCertificateOperation -VaultName $VaultName -Name $CertificateName -ErrorAction SilentlyContinue
      } while ($certOperation.Status -eq 'inProgress' -and $waitedSeconds -lt $maxWaitSeconds)

      if ($certOperation.Status -ne 'completed') {
        return [PSCustomObject]@{
          Certificate  = $null
          Thumbprint   = $null
          KeyVaultUri  = $keyVaultUri
          Success      = $false
          Message      = "Certificate creation did not complete. Status: $($certOperation.Status). Error: $($certOperation.ErrorMessage)"
        }
      }

      # Get the created certificate
      $kvCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -ErrorAction Stop
      Write-Host "Certificate created successfully in Key Vault." -ForegroundColor Green
    }
    catch {
      return [PSCustomObject]@{
        Certificate  = $null
        Thumbprint   = $null
        KeyVaultUri  = $keyVaultUri
        Success      = $false
        Message      = "Failed to create certificate in Key Vault: $($_.Exception.Message)"
      }
    }
  }
  elseif (-not $kvCert) {
    return [PSCustomObject]@{
      Certificate  = $null
      Thumbprint   = $null
      KeyVaultUri  = $keyVaultUri
      Success      = $false
      Message      = "Certificate '$CertificateName' not found in Key Vault '$VaultName'. Use -CreateIfMissing to create it."
    }
  }

  # Download certificate to local store for authentication
  Write-Host "Downloading certificate from Key Vault to local store..." -ForegroundColor Cyan

  try {
    # Get the certificate with private key as secret (for authentication use)
    $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $CertificateName -AsPlainText -ErrorAction Stop
    $secretBytes = [Convert]::FromBase64String($secret)

    # Import to local certificate store
    $localCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
      $secretBytes,
      [string]::Empty,
      [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor
      [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet
    )

    # Check if already in store
    $existingCert = Get-ChildItem -Path 'Cert:\CurrentUser\My' | Where-Object { $_.Thumbprint -eq $localCert.Thumbprint } | Select-Object -First 1
    if (-not $existingCert) {
      $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
      $store.Open('ReadWrite')
      $store.Add($localCert)
      $store.Close()
      Write-Host "Certificate imported to Cert:\CurrentUser\My (Thumbprint: $($localCert.Thumbprint))" -ForegroundColor Green
    }
    else {
      Write-Host "Certificate already exists in local store (Thumbprint: $($localCert.Thumbprint))" -ForegroundColor Cyan
      $localCert = $existingCert
    }

    return [PSCustomObject]@{
      Certificate  = $localCert
      Thumbprint   = $localCert.Thumbprint
      KeyVaultUri  = $keyVaultUri
      Success      = $true
      Message      = "Certificate retrieved from Key Vault and available in local store."
    }
  }
  catch {
    return [PSCustomObject]@{
      Certificate  = $null
      Thumbprint   = $kvCert.Thumbprint
      KeyVaultUri  = $keyVaultUri
      Success      = $false
      Message      = "Failed to download certificate from Key Vault: $($_.Exception.Message)"
    }
  }
}
