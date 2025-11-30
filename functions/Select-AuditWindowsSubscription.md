# Select-AuditWindowsSubscription

Interactively selects an Azure subscription for Key Vault operations.

## Synopsis

Lists available Azure subscriptions and prompts the user to select one. Sets the Az context to the selected subscription.

## Syntax

```powershell
Select-AuditWindowsSubscription
    [-SubscriptionId <string>]
    [-Force]
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SubscriptionId` | string | — | Select this subscription directly without prompting |
| `-Force` | switch | — | Skip prompts and use the current/default subscription |

## Output

Returns the selected `Microsoft.Azure.Commands.Profile.Models.PSAzureSubscription` object, or `$null` if cancelled.

## Prerequisites

1. **Az.Accounts module**: Install with `Install-Module -Name Az.Accounts -Scope CurrentUser`
2. **Azure authentication**: The function will prompt for `Connect-AzAccount` if not authenticated

## Examples

### Interactive selection

```powershell
$sub = Select-AuditWindowsSubscription

# Output:
# Retrieving Azure subscriptions...
#
# Available Azure Subscriptions:
#
#   [1] Production (current)
#       ID: 12345678-1234-1234-1234-123456789012
#   [2] Development
#       ID: 87654321-4321-4321-4321-210987654321
#
# Select subscription (1-2, default: 1): 2
# Selected subscription: Development
```

### Direct selection by ID

```powershell
$sub = Select-AuditWindowsSubscription -SubscriptionId '87654321-4321-4321-4321-210987654321'
```

### Non-interactive (use current)

```powershell
$sub = Select-AuditWindowsSubscription -Force
```

## Behavior

- If only one subscription exists, it's selected automatically
- The current subscription is marked and used as the default
- Invalid selections throw an error
- Sets `Set-AzContext` to the selected subscription

## Related

- [Setup-AuditWindowsApp.ps1](../README.md#setup-auditwindowsappps1) - Uses this for Key Vault setup
- [Get-AuditWindowsKeyVaultCertificate](./Get-AuditWindowsKeyVaultCertificate.md) - Key Vault certificate operations
