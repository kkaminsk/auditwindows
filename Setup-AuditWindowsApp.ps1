#requires -Version 7.0
<#
.SYNOPSIS
    Automates the Audit Windows Azure AD app registration with certificate-based authentication.
.DESCRIPTION
    Interactive workflow for administrators to provision the Audit Windows application registration. The script:
    - Creates or reuses the Audit Windows application registration (single tenant).
    - Uploads a logo if logo.jpg is present in the script directory.
    - Adds Microsoft Graph application permissions and grants administrator consent.
    - Generates or imports an X.509 certificate credential (no client secrets).
    - Outputs a JSON summary for operational records.
.PARAMETER AppDisplayName
    Display name for the application registration. Default: 'Audit Windows'
.PARAMETER CertificateSubject
    Subject name for the generated certificate. Default: 'CN=AuditWindowsCert'
.PARAMETER CertificateValidityInMonths
    Validity period for the generated certificate (1-60 months). Default: 24
.PARAMETER ExistingCertificateThumbprint
    Thumbprint of an existing certificate in Cert:\CurrentUser\My to use instead of generating a new one.
.PARAMETER SkipCertificate
    Skip certificate registration entirely. Use this for interactive-only authentication.
.PARAMETER SkipCertificateExport
    Skip exporting the certificate to .cer and .pfx files. The certificate remains in Cert:\CurrentUser\My.
.PARAMETER NonExportable
    Create the certificate with KeyExportPolicy NonExportable. This prevents the private key from being exported,
    providing stronger protection against credential theft. Trade-off: the certificate cannot be backed up or
    migrated to another machine. If the certificate is lost, you must run this script again to generate a new one.
.PARAMETER UseKeyVault
    Use Azure Key Vault for certificate storage instead of the local certificate store. Provides centralized,
    HSM-backed (with Premium SKU) certificate storage with audit logging.
.PARAMETER VaultName
    Name of the Azure Key Vault to use. Required when -UseKeyVault is specified.
.PARAMETER KeyVaultCertificateName
    Name of the certificate in Key Vault. Default: 'AuditWindowsCert'
.PARAMETER CreateVaultIfMissing
    Create the Key Vault if it does not exist. Requires -KeyVaultResourceGroupName and -KeyVaultLocation.
.PARAMETER KeyVaultResourceGroupName
    Resource group for creating a new Key Vault. Required when -CreateVaultIfMissing is specified.
.PARAMETER KeyVaultLocation
    Azure region for creating a new Key Vault. Required when -CreateVaultIfMissing is specified.
.PARAMETER KeyVaultSubscriptionId
    Azure subscription ID for Key Vault operations. If not specified, prompts for selection interactively.
.PARAMETER CertificateStoreLocation
    Certificate store location: 'LocalMachine' or 'CurrentUser'. Default: 'LocalMachine'.
    LocalMachine (Cert:\LocalMachine\My) is recommended for scheduled tasks and automation.
    CurrentUser (Cert:\CurrentUser\My) is for interactive use only.
    LocalMachine requires Administrator privileges.
.PARAMETER TenantId
    Target tenant ID. If not specified, uses the default tenant from the authenticated context.
.PARAMETER Force
    Skip confirmation prompts.
.PARAMETER Reauth
    Force re-authentication even if an existing session exists.
.PARAMETER SkipSummaryExport
    Skip exporting the summary JSON file.
.PARAMETER SummaryOutputPath
    Custom path for the summary JSON file.
.EXAMPLE
    .\Setup-AuditWindowsApp.ps1
    Creates the Audit Windows app with default settings.
.EXAMPLE
    .\Setup-AuditWindowsApp.ps1 -TenantId 'contoso.onmicrosoft.com' -Force
    Creates the app in a specific tenant without confirmation prompts.
.EXAMPLE
    .\Setup-AuditWindowsApp.ps1 -ExistingCertificateThumbprint 'ABC123...'
    Creates the app using an existing certificate from the local store.
.EXAMPLE
    .\Setup-AuditWindowsApp.ps1 -SkipCertificate
    Creates the app for interactive authentication only (no certificate for app-only auth).
.EXAMPLE
    .\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'myauditvault' -CreateVaultIfMissing -KeyVaultResourceGroupName 'rg-audit' -KeyVaultLocation 'eastus'
    Creates the app with Key Vault certificate storage, creating the vault if it doesn't exist.
.NOTES
    Requires Microsoft Graph PowerShell SDK with delegated permissions:
    Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All.
    Run as Global Administrator or Application Administrator.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$AppDisplayName = 'Audit Windows',
  [string]$CertificateSubject = 'CN=AuditWindowsCert',
  [ValidateRange(1, 60)]
  [int]$CertificateValidityInMonths = 24,
  [string]$ExistingCertificateThumbprint,
  [switch]$SkipCertificate,
  [switch]$SkipCertificateExport,
  [switch]$NonExportable,
  [switch]$UseKeyVault,
  [string]$VaultName,
  [string]$KeyVaultCertificateName = 'AuditWindowsCert',
  [switch]$CreateVaultIfMissing,
  [string]$KeyVaultResourceGroupName,
  [string]$KeyVaultLocation,
  [string]$KeyVaultSubscriptionId,
  [ValidateSet('CurrentUser', 'LocalMachine')]
  [string]$CertificateStoreLocation,
  [string]$TenantId,
  [switch]$Force,
  [switch]$Reauth,
  [switch]$SkipSummaryExport,
  [string]$SummaryOutputPath
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "This script requires PowerShell 7 or later. Detected version: $($PSVersionTable.PSVersion). Please run from pwsh."
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize timestamp and output file paths
$script:startTime = Get-Date
$script:timestamp = $script:startTime.ToString('yyyy-MM-dd-HH-mm')
$script:outputDir = if ($SummaryOutputPath) { Split-Path $SummaryOutputPath -Parent } else { $PSScriptRoot }
if (-not $script:outputDir) { $script:outputDir = $PSScriptRoot }
$script:logPath = Join-Path $script:outputDir "Setup-AuditWindowsApp-$($script:timestamp).log"
$script:jsonPath = Join-Path $script:outputDir "Setup-AuditWindowsApp-$($script:timestamp).json"

# Logging function
function Write-SetupLog {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
  )
  $logTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $logEntry = "[$logTime] [$Level] $Message"
  Add-Content -Path $script:logPath -Value $logEntry -ErrorAction SilentlyContinue
}

# Start logging
Write-SetupLog "=== Setup-AuditWindowsApp.ps1 started ===" 'INFO'
Write-SetupLog "PowerShell Version: $($PSVersionTable.PSVersion)" 'INFO'
Write-SetupLog "Log file: $($script:logPath)" 'INFO'
Write-SetupLog "JSON output: $($script:jsonPath)" 'INFO'
Write-SetupLog "Parameters: AppDisplayName=$AppDisplayName, UseKeyVault=$UseKeyVault, SkipCertificate=$SkipCertificate" 'INFO'

# Load shared helper module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules/AuditWindows.Automation.psm1'
if (-not (Test-Path -Path $modulePath)) {
  throw "Shared helper module not found at $modulePath"
}
if (Get-Module -Name AuditWindows.Automation) {
  Remove-Module -Name AuditWindows.Automation -Force
}
Import-Module $modulePath -Force

# Load functions from local .\functions folder
$functionsPath = Join-Path -Path $PSScriptRoot -ChildPath 'functions'
if (-not (Test-Path -Path $functionsPath)) {
  throw "Functions folder not found at $functionsPath"
}
Get-ChildItem -Path $functionsPath -Filter '*.ps1' | ForEach-Object {
  . $_.FullName
}

# Ensure Graph modules are available
$requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications')
foreach ($mod in $requiredModules) {
  if (-not (Get-Module -ListAvailable -Name $mod)) {
    Write-Host "Installing required module: $mod..." -ForegroundColor Yellow
    Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $mod -Force
}

# --------- Script Execution ---------
Write-Host "`n=== Audit Windows App Registration Setup ===" -ForegroundColor Cyan
Write-Host "This script will create a dedicated app registration with pre-consented Graph permissions.`n" -ForegroundColor Gray

Write-SetupLog "Connecting to Microsoft Graph..." 'INFO'
$context = Connect-AuditWindowsGraph -Reauth:$Reauth -TenantId $TenantId
$tenantId = $context.TenantId
Write-SetupLog "Connected to tenant: $tenantId" 'INFO'

Write-Host "`nTarget tenant: $tenantId" -ForegroundColor Cyan
Write-Host "Application name: $AppDisplayName" -ForegroundColor Cyan
Write-Host "Permissions to be granted:" -ForegroundColor Cyan
foreach ($perm in Get-AuditWindowsPermissionNames) {
  Write-Host " - $perm" -ForegroundColor Cyan
}

# Prompt for certificate skip if not already specified via parameter
if (-not $SkipCertificate -and -not $Force) {
  Write-Host ""
  if (Read-AuditWindowsYesNo -Prompt "Skip certificate registration? (for interactive auth only)" -Default 'N') {
    $SkipCertificate = $true
    Write-Host "Certificate registration will be skipped." -ForegroundColor Yellow
  } else {
    Write-Host "Certificate will be created for app-only authentication." -ForegroundColor Cyan
  }
}

# Prompt for certificate store location if not specified and not skipping certificate
if (-not $SkipCertificate -and -not $CertificateStoreLocation -and -not $Force) {
  Write-Host ""
  Write-Host "Certificate Store Location:" -ForegroundColor Cyan
  Write-Host "  - LocalMachine: Computer store (Cert:\LocalMachine\My) - for scheduled tasks & services" -ForegroundColor Gray
  Write-Host "  - CurrentUser:  User store (Cert:\CurrentUser\My) - for interactive use only" -ForegroundColor Gray
  Write-Host ""
  Write-Host "  [1] LocalMachine (recommended for automation)" -ForegroundColor White
  Write-Host "  [2] CurrentUser" -ForegroundColor White
  $storeChoice = Read-Host "`nSelect certificate store (1-2, default: 1)"
  # Check for admin privileges upfront
  $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

  if ($storeChoice -eq '2') {
    $CertificateStoreLocation = 'CurrentUser'
    Write-Host "Certificate will be stored in CurrentUser store." -ForegroundColor Cyan
  } elseif (-not $isAdmin) {
    # User selected LocalMachine (or default) but isn't admin - offer to use CurrentUser instead
    Write-Host ""
    Write-Host "LocalMachine store requires Administrator privileges." -ForegroundColor Yellow
    Write-Host "You are not running as Administrator." -ForegroundColor Yellow
    Write-Host ""
    if (Read-AuditWindowsYesNo -Prompt "Use CurrentUser store instead?" -Default 'Y') {
      $CertificateStoreLocation = 'CurrentUser'
      Write-Host "Certificate will be stored in CurrentUser store." -ForegroundColor Cyan
      Write-Host "Note: CurrentUser store is only accessible when you are logged in." -ForegroundColor Gray
    } else {
      Write-Host ""
      Write-Host "To use LocalMachine store:" -ForegroundColor Cyan
      Write-Host "  1. Close this PowerShell window" -ForegroundColor White
      Write-Host "  2. Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor White
      Write-Host "  3. Run this script again" -ForegroundColor White
      Write-Host ""
      exit 1
    }
  } else {
    $CertificateStoreLocation = 'LocalMachine'
    Write-Host "Certificate will be stored in LocalMachine store." -ForegroundColor Green
  }
}

# Default to LocalMachine if not set (for -Force or parameter scenarios)
if (-not $SkipCertificate -and -not $CertificateStoreLocation) {
  $CertificateStoreLocation = 'LocalMachine'
}

# Prompt for Key Vault storage if not already specified via parameter
$selectedSubscription = $null
$selectedResourceGroup = $null
$createVaultInteractive = $false
$createRgInteractive = $false
if (-not $SkipCertificate -and -not $UseKeyVault -and -not $ExistingCertificateThumbprint -and -not $Force) {
  Write-Host ""
  Write-Host "Certificate Storage Options:" -ForegroundColor Cyan
  Write-Host "  - Local Store: Certificate stored in Cert:\$CertificateStoreLocation\My (this machine only)" -ForegroundColor Gray
  Write-Host "  - Azure Key Vault: Centralized, HSM-backed storage with audit logging" -ForegroundColor Gray
  if (Read-AuditWindowsYesNo -Prompt "Use Azure Key Vault for certificate storage?" -Default 'Y') {
    $UseKeyVault = $true
    Write-Host "Key Vault storage selected." -ForegroundColor Green

    # === Gather all Key Vault information upfront ===

    # Step 1: Select Azure subscription
    Write-Host "`n--- Step 1: Select Azure Subscription ---" -ForegroundColor Cyan
    $subParams = @{ Force = $Force }
    if ($KeyVaultSubscriptionId) {
      $subParams['SubscriptionId'] = $KeyVaultSubscriptionId
    }
    $selectedSubscription = Select-AuditWindowsSubscription @subParams
    if (-not $selectedSubscription) {
      throw "Azure subscription selection cancelled."
    }

    # Step 2: Select or create resource group
    Write-Host "`n--- Step 2: Select Resource Group ---" -ForegroundColor Cyan
    if ($KeyVaultResourceGroupName) {
      # Parameter provided - verify it exists or plan to create
      $rgInfo = Get-AzResourceGroup -Name $KeyVaultResourceGroupName -ErrorAction SilentlyContinue
      if ($rgInfo) {
        $selectedResourceGroup = $rgInfo
        Write-Host "Using resource group: $KeyVaultResourceGroupName" -ForegroundColor Green
      } else {
        Write-Host "Resource group '$KeyVaultResourceGroupName' does not exist." -ForegroundColor Yellow
        if (Read-AuditWindowsYesNo -Prompt "Create resource group '$KeyVaultResourceGroupName'?" -Default 'Y') {
          $createRgInteractive = $true
          $selectedResourceGroup = @{ ResourceGroupName = $KeyVaultResourceGroupName }
          # Prompt for location if not provided
          if (-not $KeyVaultLocation) {
            $KeyVaultLocation = Read-Host "Enter Azure region for the resource group (e.g., eastus, westus2)"
            if (-not $KeyVaultLocation) {
              throw "Location is required to create resource group."
            }
          }
        } else {
          throw "Resource group '$KeyVaultResourceGroupName' does not exist."
        }
      }
    } else {
      # Interactive resource group selection
      Write-Host "Retrieving resource groups..." -ForegroundColor Gray
      $resourceGroups = @(Get-AzResourceGroup | Sort-Object ResourceGroupName)

      if ($resourceGroups.Count -eq 0) {
        Write-Host "No resource groups found in this subscription." -ForegroundColor Yellow
        Write-Host "A new resource group will be created." -ForegroundColor Cyan
        $newRgName = Read-Host "Enter name for the new resource group"
        if (-not $newRgName) {
          throw "Resource group name is required."
        }
        $KeyVaultResourceGroupName = $newRgName
        $createRgInteractive = $true
        $selectedResourceGroup = @{ ResourceGroupName = $newRgName }

        $KeyVaultLocation = Read-Host "Enter Azure region for the resource group (e.g., eastus, westus2)"
        if (-not $KeyVaultLocation) {
          throw "Location is required to create resource group."
        }
      } else {
        Write-Host "`nAvailable Resource Groups:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $resourceGroups.Count; $i++) {
          Write-Host "  [$($i + 1)] $($resourceGroups[$i].ResourceGroupName)" -ForegroundColor White
          Write-Host "       Location: $($resourceGroups[$i].Location)" -ForegroundColor Gray
        }
        Write-Host "  [N] Create a new resource group" -ForegroundColor Green

        $rgChoice = Read-Host "`nSelect resource group (1-$($resourceGroups.Count)) or N for new"

        if ($rgChoice -eq 'N' -or $rgChoice -eq 'n') {
          $newRgName = Read-Host "Enter name for the new resource group"
          if (-not $newRgName) {
            throw "Resource group name is required."
          }
          $KeyVaultResourceGroupName = $newRgName
          $createRgInteractive = $true
          $selectedResourceGroup = @{ ResourceGroupName = $newRgName }

          $KeyVaultLocation = Read-Host "Enter Azure region for the resource group (e.g., eastus, westus2)"
          if (-not $KeyVaultLocation) {
            throw "Location is required to create resource group."
          }
        } elseif ($rgChoice -match '^\d+$') {
          $rgIndex = [int]$rgChoice - 1
          if ($rgIndex -ge 0 -and $rgIndex -lt $resourceGroups.Count) {
            $selectedResourceGroup = $resourceGroups[$rgIndex]
            $KeyVaultResourceGroupName = $selectedResourceGroup.ResourceGroupName
            # Use RG location as default for vault if not specified
            if (-not $KeyVaultLocation) {
              $KeyVaultLocation = $selectedResourceGroup.Location
            }
            Write-Host "Selected resource group: $KeyVaultResourceGroupName" -ForegroundColor Green
          } else {
            throw "Invalid selection. Please enter a number between 1 and $($resourceGroups.Count)."
          }
        } else {
          throw "Invalid input. Please enter a number or 'N'."
        }
      }
    }

    # Step 3: Select or create Key Vault
    Write-Host "`n--- Step 3: Select Key Vault ---" -ForegroundColor Cyan

    # Check resource group permissions before proceeding (only for existing RGs)
    if (-not $createRgInteractive) {
      Write-Host "Checking permissions on resource group '$KeyVaultResourceGroupName'..." -ForegroundColor Gray
      try {
        # Try to list Key Vaults - this requires Microsoft.KeyVault/vaults/read permission
        $null = Get-AzKeyVault -ResourceGroupName $KeyVaultResourceGroupName -ErrorAction Stop
      }
      catch {
        if ($_.Exception.Message -match 'AuthorizationFailed|does not have authorization|Forbidden') {
          Write-Host "`nInsufficient permissions on resource group '$KeyVaultResourceGroupName'." -ForegroundColor Red
          Write-Host "You need at least 'Reader' role on the resource group to list Key Vaults," -ForegroundColor Yellow
          Write-Host "and 'Contributor' or 'Key Vault Contributor' to create new vaults." -ForegroundColor Yellow
          Write-Host "`nTo fix this, ask your Azure administrator to assign you appropriate roles on:" -ForegroundColor Cyan
          Write-Host "  Resource Group: $KeyVaultResourceGroupName" -ForegroundColor White
          Write-Host "  Subscription: $($selectedSubscription.Name)" -ForegroundColor White
          throw "Insufficient permissions on resource group '$KeyVaultResourceGroupName'."
        }
        # Other errors are OK (might just be empty RG)
      }
    }

    if ($VaultName) {
      # Parameter provided - will verify later during certificate operation
      Write-Host "Using Key Vault name: $VaultName" -ForegroundColor Green
    } else {
      # List existing vaults in the selected resource group (if RG exists)
      $existingVaults = @()
      if (-not $createRgInteractive) {
        Write-Host "Retrieving Key Vaults in resource group '$KeyVaultResourceGroupName'..." -ForegroundColor Gray
        $existingVaults = @(Get-AzKeyVault -ResourceGroupName $KeyVaultResourceGroupName -ErrorAction SilentlyContinue)
      }

      if ($existingVaults.Count -gt 0) {
        Write-Host "`nExisting Key Vaults in '$KeyVaultResourceGroupName':" -ForegroundColor Cyan
        for ($i = 0; $i -lt $existingVaults.Count; $i++) {
          Write-Host "  [$($i + 1)] $($existingVaults[$i].VaultName)" -ForegroundColor White
        }
        Write-Host "  [N] Create a new Key Vault" -ForegroundColor Green

        $vaultSelected = $false
        while (-not $vaultSelected) {
          $vaultChoice = Read-Host "`nSelect Key Vault (1-$($existingVaults.Count)) or N for new"

          if ($vaultChoice -eq 'N' -or $vaultChoice -eq 'n') {
            $VaultName = Read-Host "Enter name for the new Key Vault"
            if (-not $VaultName) {
              throw "Key Vault name is required."
            }
            $createVaultInteractive = $true
            $vaultSelected = $true
          } elseif ($vaultChoice -match '^\d+$') {
            $vaultIndex = [int]$vaultChoice - 1
            if ($vaultIndex -ge 0 -and $vaultIndex -lt $existingVaults.Count) {
              $candidateVault = $existingVaults[$vaultIndex].VaultName
              # Check if user has access to this vault before accepting selection
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
                  Write-Host "Required RBAC roles:" -ForegroundColor Yellow
                  Write-Host "  - Key Vault Certificates Officer  (to create/manage certificates)" -ForegroundColor White
                  Write-Host "  - Key Vault Secrets User          (to download certificate private key)" -ForegroundColor White

                  # Offer to assign permissions
                  if (Read-AuditWindowsYesNo -Prompt "`nWould you like to try adding these permissions now?" -Default 'Y') {
                    $currentUser = (Get-AzContext).Account.Id
                    $vaultResource = Get-AzKeyVault -VaultName $candidateVault -ErrorAction SilentlyContinue
                    if ($vaultResource) {
                      $rolesAssigned = $true
                      Write-Host "Assigning roles to $currentUser..." -ForegroundColor Cyan

                      # Key Vault Certificates Officer
                      try {
                        $existingRole1 = Get-AzRoleAssignment -Scope $vaultResource.ResourceId -RoleDefinitionName 'Key Vault Certificates Officer' -SignInName $currentUser -ErrorAction SilentlyContinue
                        if (-not $existingRole1) {
                          New-AzRoleAssignment -Scope $vaultResource.ResourceId -RoleDefinitionName 'Key Vault Certificates Officer' -SignInName $currentUser -ErrorAction Stop | Out-Null
                          Write-Host "  Assigned: Key Vault Certificates Officer" -ForegroundColor Green
                        } else {
                          Write-Host "  Already assigned: Key Vault Certificates Officer" -ForegroundColor Gray
                        }
                      }
                      catch {
                        Write-Host "  Failed to assign Key Vault Certificates Officer: $($_.Exception.Message)" -ForegroundColor Red
                        $rolesAssigned = $false
                      }

                      # Key Vault Secrets User
                      try {
                        $existingRole2 = Get-AzRoleAssignment -Scope $vaultResource.ResourceId -RoleDefinitionName 'Key Vault Secrets User' -SignInName $currentUser -ErrorAction SilentlyContinue
                        if (-not $existingRole2) {
                          New-AzRoleAssignment -Scope $vaultResource.ResourceId -RoleDefinitionName 'Key Vault Secrets User' -SignInName $currentUser -ErrorAction Stop | Out-Null
                          Write-Host "  Assigned: Key Vault Secrets User" -ForegroundColor Green
                        } else {
                          Write-Host "  Already assigned: Key Vault Secrets User" -ForegroundColor Gray
                        }
                      }
                      catch {
                        Write-Host "  Failed to assign Key Vault Secrets User: $($_.Exception.Message)" -ForegroundColor Red
                        $rolesAssigned = $false
                      }

                      if ($rolesAssigned) {
                        Write-Host "`nRoles assigned. Waiting for RBAC propagation (up to 60 seconds)..." -ForegroundColor Cyan
                        $rbacReady = $false
                        for ($retry = 1; $retry -le 12; $retry++) {
                          Start-Sleep -Seconds 5
                          try {
                            $null = Get-AzKeyVaultCertificate -VaultName $candidateVault -ErrorAction Stop
                            $rbacReady = $true
                            break
                          }
                          catch {
                            if ($_.Exception.Message -match 'Forbidden|not authorized') {
                              Write-Host "  Waiting... ($($retry * 5)s)" -ForegroundColor Gray
                            } else {
                              $rbacReady = $true
                              break
                            }
                          }
                        }

                        if ($rbacReady) {
                          Write-Host "Permissions are now active." -ForegroundColor Green
                          $VaultName = $candidateVault
                          Write-Host "Selected Key Vault: $VaultName" -ForegroundColor Green
                          $vaultSelected = $true
                        } else {
                          Write-Host "Permissions not yet propagated. Please wait 2-3 minutes and re-run the script." -ForegroundColor Yellow
                          throw "RBAC permissions not ready. Please wait and retry."
                        }
                      } else {
                        Write-Host "`nCould not assign all required roles. You may not have permission to manage RBAC on this vault." -ForegroundColor Yellow
                        Write-Host "Please select a different vault or ask an administrator to assign the roles." -ForegroundColor Yellow
                      }
                    } else {
                      Write-Host "Could not retrieve vault details. Please select a different vault." -ForegroundColor Yellow
                    }
                  } else {
                    Write-Host "Please select a different vault or create a new one." -ForegroundColor Yellow
                  }
                  # Loop continues if vault not selected
                }
                else {
                  # Other errors (like empty vault) are OK
                  $VaultName = $candidateVault
                  Write-Host "Selected Key Vault: $VaultName" -ForegroundColor Green
                  $vaultSelected = $true
                }
              }
            } else {
              Write-Host "Invalid selection. Please enter a number between 1 and $($existingVaults.Count)." -ForegroundColor Yellow
            }
          } else {
            Write-Host "Invalid input. Please enter a number or 'N'." -ForegroundColor Yellow
          }
        }
      } else {
        if ($createRgInteractive) {
          Write-Host "A new Key Vault will be created in the new resource group." -ForegroundColor Cyan
        } else {
          Write-Host "No existing Key Vaults found in resource group '$KeyVaultResourceGroupName'." -ForegroundColor Yellow
        }
        $VaultName = Read-Host "Enter name for the Key Vault"
        if (-not $VaultName) {
          throw "Key Vault name is required."
        }
        $createVaultInteractive = $true
      }
    }

    # Summary of Key Vault configuration
    Write-Host "`n--- Key Vault Configuration Summary ---" -ForegroundColor Cyan
    Write-Host "  Subscription:    $($selectedSubscription.Name)" -ForegroundColor White
    Write-Host "  Resource Group:  $KeyVaultResourceGroupName$(if ($createRgInteractive) { ' (will be created)' })" -ForegroundColor White
    Write-Host "  Key Vault:       $VaultName$(if ($createVaultInteractive) { ' (will be created)' })" -ForegroundColor White
    Write-Host "  Certificate:     $KeyVaultCertificateName" -ForegroundColor White
    Write-Host "  Local Store:     Cert:\$CertificateStoreLocation\My" -ForegroundColor White
    if ($KeyVaultLocation) {
      Write-Host "  Location:        $KeyVaultLocation" -ForegroundColor White
    }

  } else {
    Write-Host "Local certificate store (Cert:\$CertificateStoreLocation\My) will be used." -ForegroundColor Cyan
  }
}

# Prompt for non-exportable certificate if using local store and not already specified
if (-not $SkipCertificate -and -not $UseKeyVault -and -not $NonExportable -and -not $ExistingCertificateThumbprint -and -not $Force) {
  Write-Host ""
  Write-Host "Certificate Export Policy:" -ForegroundColor Cyan
  Write-Host "  - Exportable: Private key can be backed up/migrated (less secure)" -ForegroundColor Gray
  Write-Host "  - Non-Exportable: Private key cannot be exported (more secure, no backup)" -ForegroundColor Gray
  if (Read-AuditWindowsYesNo -Prompt "Create non-exportable certificate? (recommended for security)" -Default 'Y') {
    $NonExportable = $true
    Write-Host "Certificate will be created as non-exportable." -ForegroundColor Green
  } else {
    Write-Host "Certificate will be created as exportable." -ForegroundColor Yellow
  }
}

Confirm-AuditWindowsAction -Message "`nProceed with creating/updating the Audit Windows application registration?" -Force:$Force

# Create/update application
Write-SetupLog "Creating/updating application registration: $AppDisplayName" 'INFO'
$app = Set-AuditWindowsApplication -DisplayName $AppDisplayName -TenantId $tenantId
Write-SetupLog "Application registration created/updated. AppId=$($app.AppId) ObjectId=$($app.Id)" 'INFO'

# Upload logo if present
Write-SetupLog "Checking for logo file..." 'DEBUG'
$logoUploaded = Set-AuditWindowsLogo -Application $app -ScriptRoot $PSScriptRoot
Write-SetupLog "Logo upload status: $logoUploaded" 'INFO'

# Create service principal
Write-SetupLog "Creating/retrieving service principal..." 'INFO'
$sp = Get-AuditWindowsServicePrincipal -AppId $app.AppId
Write-SetupLog "Service principal ready. ObjectId=$($sp.Id)" 'INFO'

# Configure permissions and grant consent
Write-SetupLog "Configuring application permissions..." 'INFO'
Set-AuditWindowsPermissions -Application $app -ServicePrincipal $sp
Write-SetupLog "Permissions configured and admin consent granted." 'INFO'

# Add certificate credential (optional - only needed for app-only auth)
$certificate = $null
if (-not $SkipCertificate) {
  if ($UseKeyVault) {
    # Key Vault certificate storage
    if (-not $VaultName) {
      throw "-VaultName is required when using -UseKeyVault."
    }

    # Ensure Azure subscription is selected (for -UseKeyVault parameter without interactive flow)
    if (-not $selectedSubscription) {
      $subParams = @{ Force = $Force }
      if ($KeyVaultSubscriptionId) {
        $subParams['SubscriptionId'] = $KeyVaultSubscriptionId
      }
      $selectedSubscription = Select-AuditWindowsSubscription @subParams
      if (-not $selectedSubscription) {
        throw "Azure subscription selection cancelled."
      }
    }

    Write-Host "`nUsing Azure Key Vault for certificate storage..." -ForegroundColor Cyan
    Write-Host "Subscription: $($selectedSubscription.Name)" -ForegroundColor Cyan
    Write-Host "Vault: $VaultName" -ForegroundColor Cyan
    Write-Host "Certificate: $KeyVaultCertificateName" -ForegroundColor Cyan

    # Build Key Vault parameters using info gathered upfront
    $kvParams = @{
      VaultName        = $VaultName
      CertificateName  = $KeyVaultCertificateName
      CreateIfMissing  = $true
      ValidityInMonths = $CertificateValidityInMonths
      Subject          = $CertificateSubject
      StoreLocation    = $CertificateStoreLocation
    }

    # Include vault/RG creation parameters if needed (from upfront gathering or -CreateVaultIfMissing)
    if ($createVaultInteractive -or $CreateVaultIfMissing) {
      $kvParams['CreateVaultIfMissing'] = $true
      $kvParams['ResourceGroupName'] = $KeyVaultResourceGroupName
      $kvParams['Location'] = $KeyVaultLocation
    }
    if ($createRgInteractive) {
      $kvParams['CreateResourceGroupIfMissing'] = $true
    }

    Write-SetupLog "Retrieving/creating certificate from Key Vault: $VaultName/$KeyVaultCertificateName" 'INFO'
    $kvResult = Get-AuditWindowsKeyVaultCertificate @kvParams

    # Handle access denied - user doesn't have RBAC permissions on existing vault
    if (-not $kvResult.Success -and $kvResult.Message -match '^ACCESS_DENIED:') {
      Write-SetupLog "Access denied to Key Vault '$VaultName': $($kvResult.Message)" 'ERROR'
      Write-Host "`nAccess denied to Key Vault '$VaultName'." -ForegroundColor Red
      Write-Host "You need the following RBAC roles on this Key Vault:" -ForegroundColor Yellow
      Write-Host "  - Key Vault Certificates Officer (to manage certificates)" -ForegroundColor White
      Write-Host "  - Key Vault Secrets User (to download certificate with private key)" -ForegroundColor White
      Write-Host "`nTo fix this:" -ForegroundColor Cyan
      Write-Host "  1. Go to Azure Portal -> Key Vault '$VaultName' -> Access control (IAM)"
      Write-Host "  2. Click 'Add role assignment'"
      Write-Host "  3. Add both roles above to your account: $((Get-AzContext).Account.Id)"
      Write-Host "  4. Wait 2-3 minutes for propagation, then re-run this script"
      Write-Host "`nAlternatively, select a different Key Vault or create a new one." -ForegroundColor Gray
      throw "Access denied to Key Vault '$VaultName'. See instructions above."
    }

    # Handle RBAC timeout with helpful message
    if (-not $kvResult.Success -and $kvResult.Message -match '^RBAC_TIMEOUT:') {
      Write-Host "`nKey Vault was created but Azure RBAC permissions have not propagated yet." -ForegroundColor Yellow
      Write-Host "This is a known Azure limitation - role assignments can take several minutes to propagate." -ForegroundColor Yellow
      Write-Host "`nOptions:" -ForegroundColor Cyan
      Write-Host "  1. Wait 2-3 minutes and run this script again (the vault already exists)"
      Write-Host "  2. Manually assign roles in Azure Portal:" -ForegroundColor Cyan
      Write-Host "     - Go to Key Vault '$VaultName' -> Access control (IAM)"
      Write-Host "     - Add 'Key Vault Certificates Officer' role to your account"
      Write-Host "     - Add 'Key Vault Secrets User' role to your account"
      throw "RBAC permissions not ready. Please wait and retry."
    }

    if (-not $kvResult.Success) {
      Write-SetupLog "Key Vault certificate operation failed: $($kvResult.Message)" 'ERROR'
      throw "Key Vault certificate operation failed: $($kvResult.Message)"
    }

    $certificate = $kvResult.Certificate
    Write-SetupLog "Certificate retrieved from Key Vault. Thumbprint=$($certificate.Thumbprint) Expires=$($certificate.NotAfter)" 'INFO'
    Write-Host "Certificate retrieved from Key Vault (Thumbprint: $($certificate.Thumbprint))" -ForegroundColor Green

    # Attach certificate to application
    $existingKey = Find-AuditWindowsKeyCredential -KeyCredentials $app.KeyCredentials -Thumbprint $certificate.Thumbprint
    if (-not $existingKey) {
      Write-SetupLog "Attaching certificate to application registration..." 'INFO'
      Write-Host 'Attaching Key Vault certificate to application...' -ForegroundColor Cyan

      $keyCredential = @{
        Type             = 'AsymmetricX509Cert'
        Usage            = 'Verify'
        Key              = $certificate.RawData
        DisplayName      = "AuditWindows-KeyVault-$($certificate.Thumbprint)"
        StartDateTime    = $certificate.NotBefore
        EndDateTime      = $certificate.NotAfter
      }

      if ($app.KeyCredentials -and $app.KeyCredentials.Count -gt 0) {
        Write-SetupLog "Replacing $($app.KeyCredentials.Count) existing certificate(s)" 'WARN'
        Write-Host "Note: Replacing $($app.KeyCredentials.Count) existing certificate(s) with Key Vault certificate." -ForegroundColor Yellow
      }

      Update-MgApplication -ApplicationId $app.Id -KeyCredentials @($keyCredential) -ErrorAction Stop | Out-Null
      Write-SetupLog "Certificate attached to application successfully." 'INFO'
      Write-Host 'Key Vault certificate attached successfully.' -ForegroundColor Green
    } else {
      Write-SetupLog "Certificate already attached to application." 'INFO'
      Write-Host 'Key Vault certificate is already attached to the application.' -ForegroundColor Green
    }
  }
  else {
    # Local certificate store
    Write-SetupLog "Creating/retrieving local certificate. Subject=$CertificateSubject Store=$CertificateStoreLocation" 'INFO'
    $certificate = Set-AuditWindowsKeyCredential `
      -Application $app `
      -CertificateSubject $CertificateSubject `
      -CertificateValidityInMonths $CertificateValidityInMonths `
      -ExistingCertificateThumbprint $ExistingCertificateThumbprint `
      -SkipExport:$SkipCertificateExport `
      -NonExportable:$NonExportable
    Write-SetupLog "Local certificate configured. Thumbprint=$($certificate.Thumbprint)" 'INFO'
  }
} else {
  Write-SetupLog "Certificate registration skipped (interactive auth only)." 'INFO'
  Write-Host "`nSkipping certificate registration (interactive auth only)." -ForegroundColor Yellow
}

# Create comprehensive JSON output
Write-SetupLog "Creating application registration summary..." 'INFO'

$appRegistration = @{
  Metadata = @{
    GeneratedAt       = $script:startTime.ToString('o')
    GeneratedBy       = $env:USERNAME
    ComputerName      = $env:COMPUTERNAME
    ScriptVersion     = '1.0.0'
    LogFile           = $script:logPath
  }
  ApplicationRegistration = @{
    DisplayName       = $app.DisplayName
    ApplicationId     = $app.AppId
    ObjectId          = $app.Id
    TenantId          = $tenantId
    SignInAudience    = $app.SignInAudience
    CreatedDateTime   = if ($app.CreatedDateTime) { $app.CreatedDateTime.ToString('o') } else { $null }
  }
  ServicePrincipal = @{
    ObjectId          = $sp.Id
    AppId             = $sp.AppId
    DisplayName       = $sp.DisplayName
  }
  Certificate = @{
    Configured        = ($null -ne $certificate)
    Thumbprint        = if ($certificate) { $certificate.Thumbprint } else { $null }
    Subject           = if ($certificate) { $certificate.Subject } else { $null }
    NotBefore         = if ($certificate) { $certificate.NotBefore.ToString('o') } else { $null }
    NotAfter          = if ($certificate) { $certificate.NotAfter.ToString('o') } else { $null }
    StoreLocation     = if ($certificate) { $CertificateStoreLocation } else { $null }
    StorePath         = if ($certificate) { "Cert:\$CertificateStoreLocation\My" } else { $null }
    KeyVaultEnabled   = $UseKeyVault
    KeyVaultName      = if ($UseKeyVault) { $VaultName } else { $null }
    KeyVaultCertName  = if ($UseKeyVault) { $KeyVaultCertificateName } else { $null }
  }
  Permissions = @{
    Type              = 'Application'
    GrantedPermissions = @(Get-AuditWindowsPermissionNames)
    ConsentGranted    = $true
  }
  Configuration = @{
    LogoUploaded      = $logoUploaded
  }
}

# Export JSON
if (-not $SkipSummaryExport) {
  $appRegistration | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:jsonPath -Encoding UTF8
  Write-SetupLog "JSON summary exported to: $($script:jsonPath)" 'INFO'
}

# Log completion
$endTime = Get-Date
$duration = $endTime - $script:startTime
Write-SetupLog "=== Setup completed successfully in $($duration.TotalSeconds.ToString('F1')) seconds ===" 'INFO'

# Console output summary
Write-Host "`n=== Audit Windows App Registration Complete ===" -ForegroundColor Green
Write-Host "Application (client) ID: $($app.AppId)" -ForegroundColor Green
Write-Host "Directory (tenant) ID:   $tenantId" -ForegroundColor Green
if ($certificate) {
  Write-Host "Certificate thumbprint:  $($certificate.Thumbprint)" -ForegroundColor Green
  Write-Host "Certificate expires:     $($certificate.NotAfter)" -ForegroundColor Green
  Write-Host "Certificate store:       Cert:\$CertificateStoreLocation\My" -ForegroundColor Green
  if ($UseKeyVault) {
    Write-Host "Key Vault:               $VaultName" -ForegroundColor Green
  }
} else {
  Write-Host "Certificate:             Not configured (interactive auth only)" -ForegroundColor Yellow
}
Write-Host "Logo uploaded:           $logoUploaded" -ForegroundColor Green

if (-not $SkipSummaryExport) {
  Write-Host "`nOutput files:" -ForegroundColor Cyan
  Write-Host "  JSON: $($script:jsonPath)" -ForegroundColor White
  Write-Host "  Log:  $($script:logPath)" -ForegroundColor White
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
Write-Host "1. Run Get-EntraWindowsDevices.ps1 to use this dedicated app with interactive auth" -ForegroundColor White
if ($certificate) {
  Write-Host "2. Or use -UseAppAuth -TenantId '$tenantId' for certificate-based app-only auth" -ForegroundColor White
  Write-Host "3. Optionally configure Conditional Access policies targeting '$AppDisplayName'" -ForegroundColor White
} else {
  Write-Host "2. Optionally configure Conditional Access policies targeting '$AppDisplayName'" -ForegroundColor White
  Write-Host "   (Re-run with certificate to enable app-only auth for automation)" -ForegroundColor Gray
}

# Open Entra Portal
$portalUrl = "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$($app.AppId)/isMSAApp~/false"
Write-Host "`nOpening Entra Portal to the app overview..." -ForegroundColor Yellow
try {
  Start-Process $portalUrl -ErrorAction Stop
}
catch {
  Write-Host "Unable to open browser. Use this URL:" -ForegroundColor Yellow
  Write-Host $portalUrl -ForegroundColor Gray
}

# Disconnect from Graph
Disconnect-AuditWindowsGraph
