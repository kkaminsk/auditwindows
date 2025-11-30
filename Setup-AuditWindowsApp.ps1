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

$context = Connect-AuditWindowsGraph -Reauth:$Reauth -TenantId $TenantId
$tenantId = $context.TenantId

Write-Host "`nTarget tenant: $tenantId" -ForegroundColor Cyan
Write-Host "Application name: $AppDisplayName" -ForegroundColor Cyan
Write-Host "Permissions to be granted:" -ForegroundColor Cyan
foreach ($perm in Get-AuditWindowsPermissionNames) {
  Write-Host " - $perm" -ForegroundColor Cyan
}

# Prompt for certificate skip if not already specified via parameter
if (-not $SkipCertificate -and -not $Force) {
  Write-Host ""
  $skipCertResponse = Read-Host -Prompt "Skip certificate registration? (for interactive auth only) (Y/n)"
  if ($skipCertResponse -match '^[Nn]') {
    Write-Host "Certificate will be created for app-only authentication." -ForegroundColor Cyan
  } else {
    $SkipCertificate = $true
    Write-Host "Certificate registration will be skipped." -ForegroundColor Yellow
  }
}

# Prompt for non-exportable certificate if not already specified via parameter
if (-not $SkipCertificate -and -not $NonExportable -and -not $ExistingCertificateThumbprint -and -not $Force) {
  Write-Host ""
  Write-Host "Certificate Export Policy:" -ForegroundColor Cyan
  Write-Host "  - Exportable: Private key can be backed up/migrated (less secure)" -ForegroundColor Gray
  Write-Host "  - Non-Exportable: Private key cannot be exported (more secure, no backup)" -ForegroundColor Gray
  $nonExportResponse = Read-Host -Prompt "Create non-exportable certificate? (recommended for security) (Y/n)"
  if ($nonExportResponse -notmatch '^[Nn]') {
    $NonExportable = $true
    Write-Host "Certificate will be created as non-exportable." -ForegroundColor Green
  } else {
    Write-Host "Certificate will be created as exportable." -ForegroundColor Yellow
  }
}

Confirm-AuditWindowsAction -Message "`nProceed with creating/updating the Audit Windows application registration?" -Force:$Force

# Create/update application
$app = Set-AuditWindowsApplication -DisplayName $AppDisplayName -TenantId $tenantId

# Upload logo if present
$logoUploaded = Set-AuditWindowsLogo -Application $app -ScriptRoot $PSScriptRoot

# Create service principal
$sp = Get-AuditWindowsServicePrincipal -AppId $app.AppId

# Configure permissions and grant consent
Set-AuditWindowsPermissions -Application $app -ServicePrincipal $sp

# Add certificate credential (optional - only needed for app-only auth)
$certificate = $null
if (-not $SkipCertificate) {
  if ($UseKeyVault) {
    # Key Vault certificate storage
    if (-not $VaultName) {
      throw "-VaultName is required when using -UseKeyVault."
    }

    Write-Host "`nUsing Azure Key Vault for certificate storage..." -ForegroundColor Cyan
    Write-Host "Vault: $VaultName" -ForegroundColor Cyan
    Write-Host "Certificate: $KeyVaultCertificateName" -ForegroundColor Cyan

    $kvResult = Get-AuditWindowsKeyVaultCertificate `
      -VaultName $VaultName `
      -CertificateName $KeyVaultCertificateName `
      -CreateIfMissing `
      -ValidityInMonths $CertificateValidityInMonths `
      -Subject $CertificateSubject

    if (-not $kvResult.Success) {
      throw "Key Vault certificate operation failed: $($kvResult.Message)"
    }

    $certificate = $kvResult.Certificate
    Write-Host "Certificate retrieved from Key Vault (Thumbprint: $($certificate.Thumbprint))" -ForegroundColor Green

    # Attach certificate to application
    $existingKey = Find-AuditWindowsKeyCredential -KeyCredentials $app.KeyCredentials -Thumbprint $certificate.Thumbprint
    if (-not $existingKey) {
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
        Write-Host "Note: Replacing $($app.KeyCredentials.Count) existing certificate(s) with Key Vault certificate." -ForegroundColor Yellow
      }

      Update-MgApplication -ApplicationId $app.Id -KeyCredentials @($keyCredential) -ErrorAction Stop | Out-Null
      Write-Host 'Key Vault certificate attached successfully.' -ForegroundColor Green
    } else {
      Write-Host 'Key Vault certificate is already attached to the application.' -ForegroundColor Green
    }
  }
  else {
    # Local certificate store
    $certificate = Set-AuditWindowsKeyCredential `
      -Application $app `
      -CertificateSubject $CertificateSubject `
      -CertificateValidityInMonths $CertificateValidityInMonths `
      -ExistingCertificateThumbprint $ExistingCertificateThumbprint `
      -SkipExport:$SkipCertificateExport `
      -NonExportable:$NonExportable
  }
} else {
  Write-Host "`nSkipping certificate registration (interactive auth only)." -ForegroundColor Yellow
}

# Create summary
$summaryParams = @{
  AppId       = $app.AppId
  TenantId    = $tenantId
  LogoUploaded = $logoUploaded
}
if ($certificate) {
  $summaryParams['CertificateThumbprint'] = $certificate.Thumbprint
  $summaryParams['CertificateExpiration'] = $certificate.NotAfter
} else {
  $summaryParams['CertificateThumbprint'] = 'N/A (interactive only)'
  $summaryParams['CertificateExpiration'] = [datetime]::MaxValue
}
$summary = New-AuditWindowsSummaryRecord @summaryParams

# Output summary
Write-AuditWindowsSummary -Summary $summary -SkipFileExport:$SkipSummaryExport -OutputPath $SummaryOutputPath

Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
Write-Host "1. Run Get-EntraWindowsDevices.ps1 to use this dedicated app with interactive auth" -ForegroundColor White
if ($certificate) {
  Write-Host "2. Or use -UseAppAuth -TenantId '$tenantId' for certificate-based app-only auth" -ForegroundColor White
  Write-Host "3. Optionally configure Conditional Access policies targeting '$AppDisplayName'" -ForegroundColor White
} else {
  Write-Host "2. Optionally configure Conditional Access policies targeting '$AppDisplayName'" -ForegroundColor White
  Write-Host "   (Re-run with certificate to enable app-only auth for automation)" -ForegroundColor Gray
}

# Disconnect from Graph
Disconnect-AuditWindowsGraph
