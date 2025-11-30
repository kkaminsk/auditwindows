function Select-AuditWindowsSubscription {
  <#
    .SYNOPSIS
    Interactively selects an Azure subscription for Key Vault operations.
    .DESCRIPTION
    Lists available Azure subscriptions and prompts the user to select one.
    Sets the Az context to the selected subscription.
    .PARAMETER SubscriptionId
    Optional. If provided, selects this subscription directly without prompting.
    .PARAMETER Force
    Skip confirmation prompts and use the current/default subscription.
    .OUTPUTS
    Returns the selected subscription object, or $null if cancelled.
    .EXAMPLE
    $sub = Select-AuditWindowsSubscription
    .EXAMPLE
    $sub = Select-AuditWindowsSubscription -SubscriptionId '12345678-1234-1234-1234-123456789012'
  #>
  [CmdletBinding()]
  param(
    [string]$SubscriptionId,
    [switch]$Force
  )

  # Ensure Az.Accounts module is available
  if (-not (Get-Module -ListAvailable -Name 'Az.Accounts')) {
    throw "Az.Accounts module is not installed. Install it with: Install-Module -Name Az.Accounts -Scope CurrentUser"
  }

  if (-not (Get-Module -Name 'Az.Accounts')) {
    Import-Module 'Az.Accounts' -Force -ErrorAction Stop
  }

  # Check Azure authentication
  $azContext = Get-AzContext -ErrorAction SilentlyContinue
  if (-not $azContext -or -not $azContext.Account) {
    Write-Host "Not authenticated to Azure Resource Manager." -ForegroundColor Yellow
    Write-Host "A browser window will open for Azure authentication..." -ForegroundColor Cyan
    try {
      Connect-AzAccount -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
      $azContext = Get-AzContext
    }
    catch {
      throw "Azure authentication failed: $($_.Exception.Message)"
    }
  }
  else {
    Write-Host "Currently signed into Azure as: $($azContext.Account.Id)" -ForegroundColor Cyan
    if (-not $Force) {
      if (Read-AuditWindowsYesNo -Prompt "Use this account for Key Vault?" -Default 'Y') {
        Write-Host "Using Azure account: $($azContext.Account.Id)" -ForegroundColor Green
      }
      else {
        Write-Host "Signing into Azure with a different account..." -ForegroundColor Cyan
        try {
          Disconnect-AzAccount -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
          Connect-AzAccount -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
          $azContext = Get-AzContext
          Write-Host "Now using Azure account: $($azContext.Account.Id)" -ForegroundColor Green
        }
        catch {
          throw "Azure authentication failed: $($_.Exception.Message)"
        }
      }
    }
  }

  # If subscription ID provided, select it directly
  if ($SubscriptionId) {
    try {
      Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
      $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
      Write-Host "Using subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Green
      return $subscription
    }
    catch {
      throw "Failed to select subscription '$SubscriptionId': $($_.Exception.Message)"
    }
  }

  # Get all available subscriptions
  Write-Host "`nRetrieving Azure subscriptions..." -ForegroundColor Cyan
  try {
    $allSubscriptions = Get-AzSubscription -WarningAction SilentlyContinue -ErrorAction Stop
  }
  catch {
    throw "Failed to retrieve Azure subscriptions: $($_.Exception.Message)"
  }

  $subscriptions = $allSubscriptions | Where-Object { $_.State -eq 'Enabled' }

  if (-not $subscriptions -or @($subscriptions).Count -eq 0) {
    if ($allSubscriptions -and @($allSubscriptions).Count -gt 0) {
      $disabledCount = @($allSubscriptions).Count
      throw "Found $disabledCount subscription(s) but none are enabled. Check your subscription status in the Azure portal."
    }
    throw "No Azure subscriptions found for account '$($azContext.Account.Id)'. Ensure your account has access to at least one subscription."
  }

  # If only one subscription, use it
  if ($subscriptions.Count -eq 1) {
    $selected = $subscriptions[0]
    Write-Host "Using subscription: $($selected.Name) ($($selected.Id))" -ForegroundColor Green
    Set-AzContext -SubscriptionId $selected.Id -ErrorAction Stop | Out-Null
    return $selected
  }

  # If Force, use current context subscription
  if ($Force) {
    $currentSubId = $azContext.Subscription.Id
    $selected = $subscriptions | Where-Object { $_.Id -eq $currentSubId } | Select-Object -First 1
    if ($selected) {
      Write-Host "Using current subscription: $($selected.Name) ($($selected.Id))" -ForegroundColor Green
      return $selected
    }
    # Fall back to first subscription
    $selected = $subscriptions[0]
    Write-Host "Using subscription: $($selected.Name) ($($selected.Id))" -ForegroundColor Green
    Set-AzContext -SubscriptionId $selected.Id -ErrorAction Stop | Out-Null
    return $selected
  }

  # Interactive selection
  Write-Host "`nAvailable Azure Subscriptions:" -ForegroundColor Cyan
  Write-Host ""

  $index = 1
  $currentSubId = $azContext.Subscription.Id
  foreach ($sub in $subscriptions) {
    $marker = if ($sub.Id -eq $currentSubId) { " (current)" } else { "" }
    Write-Host "  [$index] $($sub.Name)$marker" -ForegroundColor White
    Write-Host "      ID: $($sub.Id)" -ForegroundColor Gray
    $index++
  }

  Write-Host ""
  $defaultIndex = 1
  # Find current subscription index
  for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    if ($subscriptions[$i].Id -eq $currentSubId) {
      $defaultIndex = $i + 1
      break
    }
  }

  $selection = Read-Host "Select subscription (1-$($subscriptions.Count), default: $defaultIndex)"

  if (-not $selection) {
    $selection = $defaultIndex
  }

  $selectionInt = 0
  if (-not [int]::TryParse($selection, [ref]$selectionInt) -or $selectionInt -lt 1 -or $selectionInt -gt $subscriptions.Count) {
    throw "Invalid selection. Please enter a number between 1 and $($subscriptions.Count)."
  }

  $selected = $subscriptions[$selectionInt - 1]
  Write-Host "Selected subscription: $($selected.Name)" -ForegroundColor Green

  # Set the context to the selected subscription
  Set-AzContext -SubscriptionId $selected.Id -ErrorAction Stop | Out-Null

  return $selected
}
