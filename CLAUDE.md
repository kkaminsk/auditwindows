<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Audit Windows - Project Guidelines

## Project Overview

Windows Audit Application (PowerShell 7+) to inventory Windows devices from Entra ID via Microsoft Graph and report BitLocker and LAPS posture. Uses certificate-based authentication for app-only (unattended) scenarios.

## Architecture

### Entry Points
- `Setup-AuditWindowsApp.ps1` - Creates/configures Azure AD app registration with certificate credentials
- `Get-EntraWindowsDevices.ps1` - Main audit script that queries devices and generates reports

### Code Organization
```
auditwindows/
├── Setup-AuditWindowsApp.ps1      # App registration setup
├── Get-EntraWindowsDevices.ps1    # Device audit execution
├── functions/                      # Reusable PowerShell functions
│   ├── *.ps1                      # Function implementations
│   └── *.md                       # Companion documentation
├── modules/
│   └── AuditWindows.Automation.psm1  # Shared helper module
└── openspec/                       # Change proposals
```

### Function Categories

**Setup Functions** (used by Setup-AuditWindowsApp.ps1):
- `Set-AuditWindowsApplication.ps1` - Create/update app registration
- `Set-AuditWindowsKeyCredential.ps1` - Certificate management
- `Set-AuditWindowsPermissions.ps1` - Grant Graph permissions
- `Get-AuditWindowsKeyVaultCertificate.ps1` - Azure Key Vault integration
- `Connect-AuditWindowsGraph.ps1` / `Disconnect-AuditWindowsGraph.ps1`

**Audit Functions** (used by Get-EntraWindowsDevices.ps1):
- `Get-WindowsDirectoryDevices.ps1` - Query Entra ID devices
- `Get-BitLockerKeysByDeviceId.ps1` - BitLocker key metadata
- `Get-ManagedDeviceByAadId.ps1` - Intune device info
- `Test-LapsAvailable.ps1` - LAPS credential check
- `Test-AuditWindowsCertificateHealth.ps1` - Certificate expiration monitoring

**Utility Functions**:
- `Write-Log.ps1` - Timestamped logging (requires `$script:logPath`)
- `Invoke-GraphWithRetry.ps1` - Graph API calls with retry/throttling
- `Read-AuditWindowsYesNo.ps1` - Interactive Y/N prompts
- `Confirm-AuditWindowsAction.ps1` - Confirmation with -Force support

## Coding Standards

### PowerShell Version
- **Required**: PowerShell 7+ (`#Requires -Version 7.0`)
- Use `pwsh` not `powershell`

### Naming Conventions
- Functions: `Verb-AuditWindowsNoun` (e.g., `Set-AuditWindowsKeyCredential`)
- Parameters: PascalCase (e.g., `-CertificateThumbprint`)
- Script variables: `$camelCase`
- Script-scoped: `$script:variableName`

### Function Structure
```powershell
function Verb-AuditWindowsNoun {
  <#
    .SYNOPSIS
    Brief one-line description.
    .DESCRIPTION
    Detailed explanation of what the function does.
    .PARAMETER ParamName
    Description of the parameter.
    .OUTPUTS
    What the function returns.
    .EXAMPLE
    Example-Usage -Param 'value'
    Description of what the example does.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RequiredParam,
    [string]$OptionalParam = 'DefaultValue',
    [switch]$SwitchParam
  )

  # Implementation
}
```

### Error Handling
- Use `$ErrorActionPreference = 'Stop'` at script level
- Use `-ErrorAction Stop` for critical operations
- Use `try/catch` for operations that need graceful failure
- Return structured objects with `Success` and `Message` properties for complex operations

### User Feedback
- Use `Write-Host` with `-ForegroundColor` for console output:
  - `Cyan` - Informational, progress
  - `Green` - Success
  - `Yellow` - Warnings, important notes
  - `Red` - Errors
  - `Gray` - Secondary info, hints
  - `White` - Menu options, key information
- Use `Write-Log` for audit trail (requires `$script:logPath`)
- Never print secrets (BitLocker keys, LAPS passwords, certificates)

### Interactive Prompts
- Use `Read-AuditWindowsYesNo` for Y/N questions (supports `-Default 'Y'` or `-Default 'N'`)
- Use `Confirm-AuditWindowsAction` for confirmations (respects `-Force` switch)
- Always provide a way to skip prompts (`-Force` parameter)

### Return Values
For complex operations, return structured objects:
```powershell
return [PSCustomObject]@{
  Success     = $true
  Data        = $result
  Message     = "Operation completed successfully."
}
```

## Documentation

### Function Documentation
Each function in `functions/` should have a companion `.md` file with:
- Synopsis
- Parameters table
- Return value description
- Usage examples
- Related functions

### Comment-Based Help
All functions must have complete comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).

## Security Guidelines

### Certificate Storage Options (in order of security)
1. **Azure Key Vault** (`-UseKeyVault`) - Production recommendation, HSM-backed
2. **Non-Exportable** (`-NonExportable`) - Cannot be extracted, single-machine
3. **Exportable** (default) - Can be backed up, least secure

### Certificate Store Locations
- `LocalMachine` (`Cert:\LocalMachine\My`) - For scheduled tasks, requires admin
- `CurrentUser` (`Cert:\CurrentUser\My`) - For interactive use only

### Never Log or Display
- BitLocker recovery keys
- LAPS passwords
- Certificate private keys
- PFX passwords

## Dependencies

### Required PowerShell Modules
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Applications`
- `Microsoft.Graph.Identity.DirectoryManagement`
- `Microsoft.Graph.DeviceManagement`

### Optional Modules
- `Az.KeyVault` - For Key Vault certificate storage
- `Az.Accounts` - Azure authentication for Key Vault

## Testing

### Manual Testing Checklist
When modifying certificate-related code:
- [ ] Test with `-NonExportable` flag
- [ ] Test with `-UseKeyVault` (requires Azure subscription)
- [ ] Test certificate health check with valid/expiring/expired certs
- [ ] Verify backward compatibility with existing exportable certificates

### Key Test Scenarios
```powershell
# Test setup with local certificate
.\Setup-AuditWindowsApp.ps1 -Force -NonExportable

# Test setup with Key Vault
.\Setup-AuditWindowsApp.ps1 -UseKeyVault -VaultName 'testvault' -Force

# Test device audit
.\Get-EntraWindowsDevices.ps1 -UseAppAuth -TenantId '<tenant>' -MaxDevices 1

# Test certificate health
Test-AuditWindowsCertificateHealth -WarningDaysBeforeExpiry 30
```

## Graph API Patterns

### Retry Logic
Always use `Invoke-GraphWithRetry` for Graph API calls:
```powershell
$result = Invoke-GraphWithRetry -OperationName 'Get-MgDevice' -Resource 'GET /devices' -Script {
  Get-MgDevice -Filter "operatingSystem eq 'Windows'" -All
}
```

### Pagination
Use `-All` parameter or `Invoke-GraphGetAll` for paginated results.

## Output Files

### Setup Script Outputs
- `Setup-AuditWindowsApp-{timestamp}.json` - App registration details
- `Setup-AuditWindowsApp-{timestamp}.log` - Execution log

### Audit Script Outputs
- `WindowsAudit-{timestamp}.xml` - Device audit report
- `WindowsAudit-{timestamp}.csv` - Summary (with `-ExportCSV`)
- `WindowsAudit-{timestamp}.log` - Execution log