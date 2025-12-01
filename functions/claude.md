# Functions Folder - Development Guidelines

This folder contains reusable PowerShell functions for the Audit Windows application.

## Folder Structure

Each function should have:
- `FunctionName.ps1` - The PowerShell function implementation
- `FunctionName.md` - Companion documentation (synopsis, parameters, examples)

## Function Categories

### App Registration & Authentication
| Function | Purpose |
|----------|---------|
| `Connect-AuditWindowsGraph` | Connect to Graph with certificate auth |
| `Connect-GraphInteractive` | Interactive Graph connection |
| `Disconnect-AuditWindowsGraph` | Disconnect from Graph |
| `Get-AuditWindowsApplication` | Retrieve app registration |
| `Get-AuditWindowsServicePrincipal` | Retrieve service principal |
| `Set-AuditWindowsApplication` | Create/update app registration |
| `Set-AuditWindowsKeyCredential` | Manage certificate credentials |
| `Set-AuditWindowsPermissions` | Configure Graph API permissions |
| `Grant-AuditWindowsConsent` | Grant admin consent |
| `Initialize-AppRegistrationAndConnect` | Combined setup workflow |

### Certificate Management
| Function | Purpose |
|----------|---------|
| `Get-AuditWindowsKeyVaultCertificate` | Retrieve cert from Azure Key Vault |
| `Test-AuditWindowsCertificateHealth` | Check certificate expiration |
| `Select-AuditWindowsSubscription` | Select Azure subscription for Key Vault |

### Device Audit
| Function | Purpose |
|----------|---------|
| `Get-WindowsDirectoryDevices` | Query Windows devices from Entra ID |
| `Get-BitLockerKeysByDeviceId` | Retrieve BitLocker key metadata |
| `Get-ManagedDeviceByAadId` | Get Intune device info by AAD ID |
| `Test-LapsAvailable` | Check LAPS credential availability |

### Graph API Utilities
| Function | Purpose |
|----------|---------|
| `Invoke-GraphWithRetry` | Graph calls with retry/throttling |
| `Invoke-GraphGet` | Single Graph GET request |
| `Invoke-GraphGetAll` | Paginated Graph GET |
| `Import-GraphModuleIfNeeded` | Lazy-load Graph modules |

### Output & Logging
| Function | Purpose |
|----------|---------|
| `Write-Log` | Timestamped logging (requires `$script:logPath`) |
| `New-AuditXml` | Create audit XML document |
| `Add-TextNode` | Add XML text node helper |
| `Write-AuditWindowsSummary` | Display audit summary |
| `Set-AuditWindowsLogo` | Set app registration logo |

### User Interaction
| Function | Purpose |
|----------|---------|
| `Read-AuditWindowsYesNo` | Y/N prompt with default |
| `Confirm-AuditWindowsAction` | Confirmation with `-Force` support |

## Adding New Functions

1. **Naming**: Use `Verb-AuditWindowsNoun` pattern
2. **Create both files**: `.ps1` implementation and `.md` documentation
3. **Include comment-based help**: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
4. **Use `[CmdletBinding()]`**: Enable common parameters

### Template

```powershell
function Verb-AuditWindowsNoun {
  <#
    .SYNOPSIS
    Brief description.
    .DESCRIPTION
    Detailed description.
    .PARAMETER ParamName
    Parameter description.
    .OUTPUTS
    Return type and description.
    .EXAMPLE
    Verb-AuditWindowsNoun -ParamName 'value'
    Example description.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$ParamName
  )

  # Implementation
}
```

## Testing Functions

Test functions by dot-sourcing:

```powershell
. .\functions\FunctionName.ps1
FunctionName -Param 'value'
```

Or import all functions:

```powershell
Get-ChildItem -Path .\functions\*.ps1 | ForEach-Object { . $_.FullName }
```

## Security Reminders

- Never log or return secrets (BitLocker keys, LAPS passwords, certificate private keys)
- Use `[SecureString]` for sensitive parameters when appropriate
- Validate inputs at function boundaries
