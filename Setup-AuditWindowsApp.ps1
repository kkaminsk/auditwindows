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

Confirm-AuditWindowsAction -Message "`nProceed with creating/updating the Audit Windows application registration?" -Force:$Force

# Create/update application
$app = Set-AuditWindowsApplication -DisplayName $AppDisplayName -TenantId $tenantId

# Upload logo if present
$logoUploaded = Set-AuditWindowsLogo -Application $app -ScriptRoot $PSScriptRoot

# Create service principal
$sp = Get-AuditWindowsServicePrincipal -AppId $app.AppId

# Configure permissions and grant consent
Set-AuditWindowsPermissions -Application $app -ServicePrincipal $sp

# Add certificate credential
$certificate = Set-AuditWindowsKeyCredential `
  -Application $app `
  -CertificateSubject $CertificateSubject `
  -CertificateValidityInMonths $CertificateValidityInMonths `
  -ExistingCertificateThumbprint $ExistingCertificateThumbprint

# Create summary
$summary = New-AuditWindowsSummaryRecord `
  -AppId $app.AppId `
  -TenantId $tenantId `
  -CertificateThumbprint $certificate.Thumbprint `
  -CertificateExpiration $certificate.NotAfter `
  -LogoUploaded $logoUploaded

# Output summary
Write-AuditWindowsSummary -Summary $summary -SkipFileExport:$SkipSummaryExport -OutputPath $SummaryOutputPath

Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
Write-Host "1. Run Get-EntraWindowsDevices.ps1 with -UseAppRegistration to use this dedicated app" -ForegroundColor White
Write-Host "2. Or use -UseAppAuth -TenantId '$tenantId' for certificate-based app-only auth" -ForegroundColor White
Write-Host "3. Optionally configure Conditional Access policies targeting '$AppDisplayName'" -ForegroundColor White
