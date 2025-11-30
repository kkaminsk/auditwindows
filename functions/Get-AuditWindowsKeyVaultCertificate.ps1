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
    [switch]$CreateVaultIfMissing,
    [string]$ResourceGroupName,
    [string]$Location,
    [switch]$CreateResourceGroupIfMissing,
    [int]$ValidityInMonths = 24,
    [string]$Subject = 'CN=AuditWindowsCert',
    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$StoreLocation = 'CurrentUser'
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

  # Check if vault exists and create if needed
  $vault = $null
  $vaultMissing = $false
  try {
    $vault = Get-AzKeyVault -VaultName $VaultName -ErrorAction Stop
    if (-not $vault) {
      $vaultMissing = $true
    }
  }
  catch {
    # DNS errors or other access issues indicate vault doesn't exist or isn't reachable
    if ($_.Exception.Message -match 'not found|No such host|could not be found|does not exist') {
      $vaultMissing = $true
    }
    else {
      return [PSCustomObject]@{
        Certificate  = $null
        Thumbprint   = $null
        KeyVaultUri  = $keyVaultUri
        Success      = $false
        Message      = "Failed to access Key Vault: $($_.Exception.Message)"
      }
    }
  }

  if ($vaultMissing) {
    if ($CreateVaultIfMissing) {
      if (-not $ResourceGroupName -or -not $Location) {
        return [PSCustomObject]@{
          Certificate  = $null
          Thumbprint   = $null
          KeyVaultUri  = $keyVaultUri
          Success      = $false
          Message      = "VAULT_MISSING:Key Vault '$VaultName' does not exist. Provide -ResourceGroupName and -Location to create it."
        }
      }

      # Check if resource group exists
      $rgExists = $null
      try {
        $rgExists = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
      }
      catch {
        # Resource group doesn't exist
      }

      if (-not $rgExists) {
        if ($CreateResourceGroupIfMissing) {
          Write-Host "Resource group '$ResourceGroupName' not found. Creating in location '$Location'..." -ForegroundColor Cyan
          try {
            New-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Stop | Out-Null
            Write-Host "Resource group '$ResourceGroupName' created successfully." -ForegroundColor Green
          }
          catch {
            return [PSCustomObject]@{
              Certificate  = $null
              Thumbprint   = $null
              KeyVaultUri  = $keyVaultUri
              Success      = $false
              Message      = "RG_CREATE_FAILED:Failed to create resource group '$ResourceGroupName': $($_.Exception.Message)"
            }
          }
        }
        else {
          return [PSCustomObject]@{
            Certificate  = $null
            Thumbprint   = $null
            KeyVaultUri  = $keyVaultUri
            Success      = $false
            Message      = "RG_MISSING:Resource group '$ResourceGroupName' does not exist."
          }
        }
      }

      Write-Host "Key Vault '$VaultName' not found. Creating in resource group '$ResourceGroupName'..." -ForegroundColor Cyan
      try {
        $vault = New-AzKeyVault -VaultName $VaultName -ResourceGroupName $ResourceGroupName -Location $Location -ErrorAction Stop
        Write-Host "Key Vault '$VaultName' created successfully." -ForegroundColor Green

        # Wait for RBAC propagation - Azure role assignments can take up to 10 minutes
        # We use a retry loop with exponential backoff instead of a fixed delay
        Write-Host "Waiting for RBAC permissions to propagate (this may take up to 60 seconds)..." -ForegroundColor Cyan
        $maxRetries = 12
        $retryCount = 0
        $rbacReady = $false
        while (-not $rbacReady -and $retryCount -lt $maxRetries) {
          Start-Sleep -Seconds 5
          $retryCount++
          try {
            # Test access by listing certificates (requires Certificate List permission)
            $null = Get-AzKeyVaultCertificate -VaultName $VaultName -ErrorAction Stop
            $rbacReady = $true
            Write-Host "RBAC permissions are now active." -ForegroundColor Green
          }
          catch {
            if ($_.Exception.Message -match 'Forbidden|not authorized|Unauthorized') {
              Write-Host "  Waiting for permissions... ($($retryCount * 5)s)" -ForegroundColor Gray
            }
            else {
              # Other errors might be OK (e.g., no certificates found)
              $rbacReady = $true
            }
          }
        }

        if (-not $rbacReady) {
          return [PSCustomObject]@{
            Certificate  = $null
            Thumbprint   = $null
            KeyVaultUri  = $keyVaultUri
            Success      = $false
            Message      = "RBAC_TIMEOUT:Key Vault created but permissions did not propagate within 60 seconds. Please wait a few minutes and try again, or manually assign 'Key Vault Certificates Officer' and 'Key Vault Secrets User' roles to your account."
          }
        }
      }
      catch {
        return [PSCustomObject]@{
          Certificate  = $null
          Thumbprint   = $null
          KeyVaultUri  = $keyVaultUri
          Success      = $false
          Message      = "Failed to create Key Vault: $($_.Exception.Message)"
        }
      }
    }
    else {
      return [PSCustomObject]@{
        Certificate  = $null
        Thumbprint   = $null
        KeyVaultUri  = $keyVaultUri
        Success      = $false
        Message      = "VAULT_MISSING:Key Vault '$VaultName' does not exist."
      }
    }
  }

  # Try to get existing certificate
  try {
    $kvCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -ErrorAction Stop
  }
  catch {
    if ($_.Exception.Message -match 'Forbidden|not authorized|Unauthorized|Caller is not authorized') {
      return [PSCustomObject]@{
        Certificate  = $null
        Thumbprint   = $null
        KeyVaultUri  = $keyVaultUri
        Success      = $false
        Message      = "ACCESS_DENIED:You don't have permission to access Key Vault '$VaultName'. Assign 'Key Vault Certificates Officer' and 'Key Vault Secrets User' roles to your account in Azure Portal (Access control IAM)."
      }
    }
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
      # Note: -KeyNotExportable makes the private key non-exportable from Key Vault
      # We set it to $false (exportable) so the script can download the cert with private key
      $policy = New-AzKeyVaultCertificatePolicy `
        -SubjectName $Subject `
        -IssuerName 'Self' `
        -ValidityInMonths $ValidityInMonths `
        -KeyType 'RSA' `
        -KeySize 2048 `
        -ReuseKeyOnRenewal `
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
  $storePath = "Cert:\$StoreLocation\My"
  Write-Host "Downloading certificate from Key Vault to $storePath..." -ForegroundColor Cyan

  try {
    # Get the certificate with private key as secret (for authentication use)
    $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $CertificateName -AsPlainText -ErrorAction Stop
    $secretBytes = [Convert]::FromBase64String($secret)

    # Import to certificate store with appropriate key storage flags
    $keyFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    if ($StoreLocation -eq 'LocalMachine') {
      $keyFlags = $keyFlags -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet
    } else {
      $keyFlags = $keyFlags -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet
    }

    $localCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
      $secretBytes,
      [string]::Empty,
      $keyFlags
    )

    # Check if already in store
    $existingCert = Get-ChildItem -Path $storePath | Where-Object { $_.Thumbprint -eq $localCert.Thumbprint } | Select-Object -First 1
    if (-not $existingCert) {
      $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', $StoreLocation)
      $store.Open('ReadWrite')
      $store.Add($localCert)
      $store.Close()
      Write-Host "Certificate imported to $storePath (Thumbprint: $($localCert.Thumbprint))" -ForegroundColor Green
    }
    else {
      Write-Host "Certificate already exists in $storePath (Thumbprint: $($localCert.Thumbprint))" -ForegroundColor Cyan
      $localCert = $existingCert
    }

    return [PSCustomObject]@{
      Certificate  = $localCert
      Thumbprint   = $localCert.Thumbprint
      KeyVaultUri  = $keyVaultUri
      Success      = $true
      Message      = "Certificate retrieved from Key Vault and available in $storePath."
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
