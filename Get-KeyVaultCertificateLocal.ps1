#requires -Version 7.0
<#
.SYNOPSIS
    Downloads a certificate from Azure Key Vault to the local certificate store.
.DESCRIPTION
    Standalone utility to retrieve a certificate (with private key) from Azure Key Vault
    and import it to the local certificate store. Useful for:
    - Setting up app-only authentication on a new machine
    - Refreshing a certificate after rotation in Key Vault
    - Testing Key Vault connectivity and permissions

    By default, imports to Cert:\LocalMachine\My (computer store) for scheduled tasks.
    Use -CurrentUser to import to Cert:\CurrentUser\My for interactive use only.

    If VaultName is not provided, the script will guide you through selecting:
    1. An existing JSON configuration file from Setup-AuditWindowsApp.ps1, OR
    2. Azure subscription → Resource Group → Key Vault interactively
.PARAMETER VaultName
    Name of the Azure Key Vault containing the certificate. If not specified, prompts to
    select from available JSON configuration files or browse Azure interactively.
.PARAMETER CertificateName
    Name of the certificate in Key Vault. Default: 'AuditWindowsCert'
.PARAMETER SubscriptionId
    Azure subscription ID. If not specified, prompts for selection interactively.
.PARAMETER ResourceGroupName
    Resource group containing the Key Vault. If not specified, prompts for selection.
.PARAMETER CurrentUser
    Import to Cert:\CurrentUser\My (user store) instead of Cert:\LocalMachine\My.
    Use this for interactive scenarios only. LocalMachine is default for automation.
.PARAMETER Force
    Skip confirmation prompts.
.EXAMPLE
    .\Get-KeyVaultCertificateLocal.ps1
    Interactive mode - select from JSON configs or browse Azure for Key Vault.
.EXAMPLE
    .\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault'
    Downloads the certificate to the computer store (LocalMachine).
.EXAMPLE
    .\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault' -CurrentUser
    Downloads the certificate to the user store (CurrentUser).
.EXAMPLE
    .\Get-KeyVaultCertificateLocal.ps1 -VaultName 'mykeyvault' -CertificateName 'MyCert' -SubscriptionId '12345...'
    Downloads a specific certificate using a specific subscription.
.NOTES
    Requires:
    - Az.Accounts and Az.KeyVault PowerShell modules
    - Key Vault Secrets User role on the Key Vault (to download private key)
    - Key Vault Certificates Officer role (to read certificate metadata)
    - Administrator privileges when using LocalMachine store (default)
#>
[CmdletBinding()]
param(
    [string]$VaultName,

    [string]$CertificateName = 'AuditWindowsCert',

    [string]$SubscriptionId,

    [string]$ResourceGroupName,

    [switch]$CurrentUser,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determine certificate store (default to LocalMachine for automation)
$storeLocation = if ($CurrentUser) { 'CurrentUser' } else { 'LocalMachine' }
$storePath = "Cert:\$storeLocation\My"

# Check for Administrator privileges if using LocalMachine store
if (-not $CurrentUser) {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "`nLocalMachine store requires Administrator privileges." -ForegroundColor Yellow
        Write-Host "You are not running as Administrator." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  1. Restart PowerShell as Administrator (recommended for automation)" -ForegroundColor White
        Write-Host "  2. Use -CurrentUser switch for interactive use only" -ForegroundColor White
        Write-Host ""
        throw "Administrator privileges required for LocalMachine certificate store."
    }
}

# Load helper functions
$functionsPath = Join-Path -Path $PSScriptRoot -ChildPath 'functions'
if (-not (Test-Path -Path $functionsPath)) {
    throw "Functions folder not found at $functionsPath. Run this script from the auditwindows directory."
}

# Load required functions
. (Join-Path $functionsPath 'Get-AuditWindowsKeyVaultCertificate.ps1')
. (Join-Path $functionsPath 'Read-AuditWindowsYesNo.ps1')
. (Join-Path $functionsPath 'Select-AuditWindowsSubscription.ps1')

# Ensure Az modules are available
$requiredModules = @('Az.Accounts', 'Az.KeyVault', 'Az.Resources')
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Host "Installing required module: $mod..." -ForegroundColor Yellow
        Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $mod -Force
}

Write-Host "`n=== Key Vault Certificate Download ===" -ForegroundColor Cyan
Write-Host "Target Store: $storePath" -ForegroundColor White

# Track if we got config from JSON
$configFromJson = $false
$selectedSubscription = $null

# If VaultName not provided, offer options
if (-not $VaultName) {
    Write-Host "`n--- Configuration Source ---" -ForegroundColor Cyan

    # Find Setup-AuditWindowsApp JSON files
    $jsonFiles = @(Get-ChildItem -Path $PSScriptRoot -Filter 'Setup-AuditWindowsApp-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

    $configOptions = @()
    if ($jsonFiles.Count -gt 0) {
        Write-Host "Found $($jsonFiles.Count) configuration file(s):" -ForegroundColor White
        Write-Host ""

        $index = 1
        foreach ($jsonFile in $jsonFiles) {
            try {
                $config = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json
                $kvName = $config.Certificate.KeyVaultName
                $certName = $config.Certificate.KeyVaultCertName
                $thumbprint = $config.Certificate.Thumbprint
                $appId = $config.ApplicationRegistration.ApplicationId
                $timestamp = $config.Metadata.GeneratedAt

                if ($kvName) {
                    $configOptions += @{
                        Index = $index
                        File = $jsonFile
                        VaultName = $kvName
                        CertificateName = $certName
                        Thumbprint = $thumbprint
                        AppId = $appId
                        Timestamp = $timestamp
                    }

                    Write-Host "  [$index] $($jsonFile.Name)" -ForegroundColor White
                    Write-Host "      Key Vault: $kvName" -ForegroundColor Gray
                    Write-Host "      Certificate: $certName (Thumbprint: $thumbprint)" -ForegroundColor Gray
                    Write-Host "      App ID: $appId" -ForegroundColor Gray
                    Write-Host ""
                    $index++
                }
            }
            catch {
                # Skip invalid JSON files
            }
        }
    }

    if ($configOptions.Count -gt 0) {
        Write-Host "  [B] Browse Azure for Key Vault" -ForegroundColor Green
        Write-Host ""

        $selection = Read-Host "Select configuration (1-$($configOptions.Count)) or B to browse Azure"

        if ($selection -eq 'B' -or $selection -eq 'b') {
            # Will fall through to Azure browsing below
            $VaultName = $null
        }
        elseif ($selection -match '^\d+$') {
            $selIndex = [int]$selection
            $selected = $configOptions | Where-Object { $_.Index -eq $selIndex }
            if ($selected) {
                $VaultName = $selected.VaultName
                if ($selected.CertificateName) {
                    $CertificateName = $selected.CertificateName
                }
                $configFromJson = $true
                Write-Host "`nUsing configuration from: $($selected.File.Name)" -ForegroundColor Green
                Write-Host "  Vault: $VaultName" -ForegroundColor Cyan
                Write-Host "  Certificate: $CertificateName" -ForegroundColor Cyan
                if ($selected.Thumbprint) {
                    Write-Host "  Expected Thumbprint: $($selected.Thumbprint)" -ForegroundColor Cyan
                }
            }
            else {
                throw "Invalid selection. Please enter a number between 1 and $($configOptions.Count)."
            }
        }
        else {
            throw "Invalid input. Please enter a number or 'B'."
        }
    }
    else {
        Write-Host "No Setup-AuditWindowsApp JSON files found." -ForegroundColor Yellow
        Write-Host "Will browse Azure for Key Vault selection." -ForegroundColor Gray
    }
}

# If still no VaultName, browse Azure (subscription -> resource group -> vault)
if (-not $VaultName) {
    Write-Host "`n--- Browse Azure for Key Vault ---" -ForegroundColor Cyan

    # Step 1: Select Azure subscription
    Write-Host "`n--- Step 1: Select Azure Subscription ---" -ForegroundColor Cyan
    $subParams = @{ Force = $Force }
    if ($SubscriptionId) {
        $subParams['SubscriptionId'] = $SubscriptionId
    }
    $selectedSubscription = Select-AuditWindowsSubscription @subParams
    if (-not $selectedSubscription) {
        throw "Azure subscription selection cancelled."
    }

    # Step 2: Select resource group
    Write-Host "`n--- Step 2: Select Resource Group ---" -ForegroundColor Cyan
    if ($ResourceGroupName) {
        # Parameter provided - verify it exists
        $rgInfo = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $rgInfo) {
            throw "Resource group '$ResourceGroupName' not found."
        }
        Write-Host "Using resource group: $ResourceGroupName" -ForegroundColor Green
    }
    else {
        # Interactive resource group selection
        Write-Host "Retrieving resource groups..." -ForegroundColor Gray
        $resourceGroups = @(Get-AzResourceGroup | Sort-Object ResourceGroupName)

        if ($resourceGroups.Count -eq 0) {
            throw "No resource groups found in this subscription."
        }

        Write-Host "`nAvailable Resource Groups:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $resourceGroups.Count; $i++) {
            Write-Host "  [$($i + 1)] $($resourceGroups[$i].ResourceGroupName)" -ForegroundColor White
            Write-Host "       Location: $($resourceGroups[$i].Location)" -ForegroundColor Gray
        }

        $rgChoice = Read-Host "`nSelect resource group (1-$($resourceGroups.Count))"

        if ($rgChoice -match '^\d+$') {
            $rgIndex = [int]$rgChoice - 1
            if ($rgIndex -ge 0 -and $rgIndex -lt $resourceGroups.Count) {
                $ResourceGroupName = $resourceGroups[$rgIndex].ResourceGroupName
                Write-Host "Selected resource group: $ResourceGroupName" -ForegroundColor Green
            }
            else {
                throw "Invalid selection. Please enter a number between 1 and $($resourceGroups.Count)."
            }
        }
        else {
            throw "Invalid input. Please enter a number."
        }
    }

    # Step 3: Select Key Vault
    Write-Host "`n--- Step 3: Select Key Vault ---" -ForegroundColor Cyan

    # Check resource group permissions
    Write-Host "Retrieving Key Vaults in resource group '$ResourceGroupName'..." -ForegroundColor Gray
    try {
        $existingVaults = @(Get-AzKeyVault -ResourceGroupName $ResourceGroupName -ErrorAction Stop)
    }
    catch {
        if ($_.Exception.Message -match 'AuthorizationFailed|does not have authorization|Forbidden') {
            Write-Host "`nInsufficient permissions on resource group '$ResourceGroupName'." -ForegroundColor Red
            Write-Host "You need at least 'Reader' role on the resource group to list Key Vaults." -ForegroundColor Yellow
            throw "Insufficient permissions on resource group."
        }
        throw
    }

    if ($existingVaults.Count -eq 0) {
        throw "No Key Vaults found in resource group '$ResourceGroupName'."
    }

    Write-Host "`nAvailable Key Vaults in '$ResourceGroupName':" -ForegroundColor Cyan
    for ($i = 0; $i -lt $existingVaults.Count; $i++) {
        Write-Host "  [$($i + 1)] $($existingVaults[$i].VaultName)" -ForegroundColor White
    }

    $vaultSelected = $false
    while (-not $vaultSelected) {
        $vaultChoice = Read-Host "`nSelect Key Vault (1-$($existingVaults.Count))"

        if ($vaultChoice -match '^\d+$') {
            $vaultIndex = [int]$vaultChoice - 1
            if ($vaultIndex -ge 0 -and $vaultIndex -lt $existingVaults.Count) {
                $candidateVault = $existingVaults[$vaultIndex].VaultName

                # Check if user has access to this vault
                Write-Host "Checking access to '$candidateVault'..." -ForegroundColor Gray
                try {
                    $null = Get-AzKeyVaultCertificate -VaultName $candidateVault -ErrorAction Stop
                    $VaultName = $candidateVault
                    Write-Host "Selected Key Vault: $VaultName" -ForegroundColor Green
                    $vaultSelected = $true
                }
                catch {
                    if ($_.Exception.Message -match 'Forbidden|not authorized|Unauthorized|Caller is not authorized') {
                        Write-Host "`nAccess denied to Key Vault '$candidateVault'." -ForegroundColor Red
                        Write-Host "Required RBAC roles (assign in Azure Portal -> Key Vault -> Access control IAM):" -ForegroundColor Yellow
                        Write-Host "  - Key Vault Certificates Officer  (to read certificates)" -ForegroundColor White
                        Write-Host "  - Key Vault Secrets User          (to download private key)" -ForegroundColor White
                        Write-Host "Please select a different vault or fix permissions and re-run." -ForegroundColor Yellow
                        # Loop continues
                    }
                    else {
                        # Other errors (like empty vault) are OK
                        $VaultName = $candidateVault
                        Write-Host "Selected Key Vault: $VaultName" -ForegroundColor Green
                        $vaultSelected = $true
                    }
                }
            }
            else {
                Write-Host "Invalid selection. Please enter a number between 1 and $($existingVaults.Count)." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Yellow
        }
    }

    # Step 4: Select Certificate
    Write-Host "`n--- Step 4: Select Certificate ---" -ForegroundColor Cyan
    Write-Host "Retrieving certificates from '$VaultName'..." -ForegroundColor Gray

    try {
        $certificates = @(Get-AzKeyVaultCertificate -VaultName $VaultName -ErrorAction Stop)
    }
    catch {
        throw "Failed to list certificates: $($_.Exception.Message)"
    }

    if ($certificates.Count -eq 0) {
        throw "No certificates found in Key Vault '$VaultName'. Run Setup-AuditWindowsApp.ps1 to create one."
    }

    Write-Host "`nAvailable Certificates in '$VaultName':" -ForegroundColor Cyan
    for ($i = 0; $i -lt $certificates.Count; $i++) {
        $certInfo = $certificates[$i]
        $certName = $certInfo.Name

        # Get full certificate details to access thumbprint
        $certDetails = $null
        try {
            $certDetails = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $certName -ErrorAction Stop
        } catch {
            # If we can't get details, just show the name
        }

        # Get thumbprint - try various property names used by different Az.KeyVault versions
        $thumbprint = 'N/A'
        if ($certDetails) {
            $thumbprint = $certDetails.Thumbprint -as [string]
            if (-not $thumbprint) { $thumbprint = $certDetails.X509ThumbprintHex -as [string] }
            if (-not $thumbprint -and $certDetails.X509Thumbprint) {
                $thumbprint = [BitConverter]::ToString($certDetails.X509Thumbprint) -replace '-', ''
            }
            if (-not $thumbprint) { $thumbprint = 'N/A' }
        }

        # Get expiration - use null-safe access
        $expires = 'N/A'
        $attrExpires = $null
        if ($certDetails -and $null -ne $certDetails.PSObject.Properties['Attributes']) {
            $attrs = $certDetails.Attributes
            if ($null -ne $attrs -and $null -ne $attrs.PSObject.Properties['Expires']) {
                $attrExpires = $attrs.Expires
            }
        }
        if (-not $attrExpires -and $certInfo -and $null -ne $certInfo.PSObject.Properties['Attributes']) {
            $attrs = $certInfo.Attributes
            if ($null -ne $attrs -and $null -ne $attrs.PSObject.Properties['Expires']) {
                $attrExpires = $attrs.Expires
            }
        }
        if ($attrExpires) {
            $expires = $attrExpires.ToString('yyyy-MM-dd')
        }

        Write-Host "  [$($i + 1)] $certName" -ForegroundColor White
        Write-Host "       Thumbprint: $thumbprint" -ForegroundColor Gray
        Write-Host "       Expires: $expires" -ForegroundColor Gray
    }

    $certChoice = Read-Host "`nSelect certificate (1-$($certificates.Count), default: 1)"
    if (-not $certChoice) { $certChoice = '1' }

    if ($certChoice -match '^\d+$') {
        $certIndex = [int]$certChoice - 1
        if ($certIndex -ge 0 -and $certIndex -lt $certificates.Count) {
            $CertificateName = $certificates[$certIndex].Name
            Write-Host "Selected certificate: $CertificateName" -ForegroundColor Green
        }
        else {
            throw "Invalid selection."
        }
    }
    else {
        throw "Invalid input."
    }
}

# Ensure subscription is selected if we got config from JSON
if (-not $selectedSubscription) {
    Write-Host "`n--- Azure Authentication ---" -ForegroundColor Cyan
    $subParams = @{ Force = $Force }
    if ($SubscriptionId) {
        $subParams['SubscriptionId'] = $SubscriptionId
    }
    $selectedSubscription = Select-AuditWindowsSubscription @subParams
    if (-not $selectedSubscription) {
        throw "Azure subscription selection cancelled."
    }
}

# Summary before download
Write-Host "`n--- Download Summary ---" -ForegroundColor Cyan
Write-Host "Subscription: $($selectedSubscription.Name)" -ForegroundColor White
Write-Host "Key Vault:    $VaultName" -ForegroundColor White
Write-Host "Certificate:  $CertificateName" -ForegroundColor White
Write-Host "Target Store: $storePath" -ForegroundColor White

# Check if certificate already exists locally
Write-Host "`n--- Checking Local Certificate Store ---" -ForegroundColor Cyan
$existingCerts = @(Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'AuditWindows' -or $_.FriendlyName -match 'AuditWindows' })
if ($existingCerts.Count -gt 0) {
    Write-Host "Found $($existingCerts.Count) existing certificate(s) that may be related:" -ForegroundColor Yellow
    foreach ($cert in $existingCerts) {
        Write-Host "  - $($cert.Subject) (Thumbprint: $($cert.Thumbprint), Expires: $($cert.NotAfter))" -ForegroundColor Gray
    }
}

# Confirm before proceeding
if (-not $Force) {
    Write-Host ""
    if (-not (Read-AuditWindowsYesNo -Prompt "Download certificate from Key Vault?" -Default 'Y')) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Download certificate
Write-Host "`n--- Downloading Certificate ---" -ForegroundColor Cyan
$result = Get-AuditWindowsKeyVaultCertificate -VaultName $VaultName -CertificateName $CertificateName -StoreLocation $storeLocation

if (-not $result.Success) {
    Write-Host "`nFailed to download certificate." -ForegroundColor Red

    # Provide specific guidance based on error
    if ($result.Message -match 'ACCESS_DENIED') {
        Write-Host "`nYou need the following RBAC roles on Key Vault '$VaultName':" -ForegroundColor Yellow
        Write-Host "  - Key Vault Certificates Officer  (to read certificate metadata)" -ForegroundColor White
        Write-Host "  - Key Vault Secrets User          (to download private key)" -ForegroundColor White
        Write-Host "`nAssign these roles in: Azure Portal -> Key Vault -> Access control (IAM)" -ForegroundColor Cyan
    }
    elseif ($result.Message -match 'VAULT_MISSING') {
        Write-Host "`nKey Vault '$VaultName' was not found." -ForegroundColor Yellow
        Write-Host "Verify the vault name and ensure you have access to it." -ForegroundColor Cyan
    }
    elseif ($result.Message -match 'NotFound|does not exist') {
        Write-Host "`nCertificate '$CertificateName' was not found in Key Vault '$VaultName'." -ForegroundColor Yellow
        Write-Host "Use Setup-AuditWindowsApp.ps1 to create the certificate first." -ForegroundColor Cyan
    }
    else {
        Write-Host "Error: $($result.Message)" -ForegroundColor Red
    }

    exit 1
}

# Success
Write-Host "`n=== Certificate Downloaded Successfully ===" -ForegroundColor Green
Write-Host "Thumbprint:  $($result.Thumbprint)" -ForegroundColor White
Write-Host "Location:    $storePath" -ForegroundColor White
Write-Host "Key Vault:   $($result.KeyVaultUri)" -ForegroundColor White

# Show certificate details
$cert = $result.Certificate
Write-Host "`nCertificate Details:" -ForegroundColor Cyan
Write-Host "  Subject:         $($cert.Subject)" -ForegroundColor Gray
Write-Host "  Issuer:          $($cert.Issuer)" -ForegroundColor Gray
Write-Host "  Valid From:      $($cert.NotBefore)" -ForegroundColor Gray
Write-Host "  Valid Until:     $($cert.NotAfter)" -ForegroundColor Gray
Write-Host "  Has Private Key: $($cert.HasPrivateKey)" -ForegroundColor Gray

# Calculate days until expiration
$daysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days
if ($daysUntilExpiry -lt 30) {
    Write-Host "`nWARNING: Certificate expires in $daysUntilExpiry days!" -ForegroundColor Red
}
elseif ($daysUntilExpiry -lt 90) {
    Write-Host "`nNote: Certificate expires in $daysUntilExpiry days." -ForegroundColor Yellow
}
else {
    Write-Host "`nCertificate valid for $daysUntilExpiry more days." -ForegroundColor Green
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
Write-Host "Use this certificate with Get-EntraWindowsDevices.ps1:" -ForegroundColor White
Write-Host "  .\Get-EntraWindowsDevices.ps1 -UseAppAuth -CertificateThumbprint '$($result.Thumbprint)'" -ForegroundColor Cyan
