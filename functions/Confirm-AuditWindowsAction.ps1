function Confirm-AuditWindowsAction {
  <#
    .SYNOPSIS
    Prompts for confirmation before proceeding with an action.
  #>
  param(
    [Parameter(Mandatory)]
    [string]$Message,
    [switch]$Force
  )

  if ($Force) {
    return
  }

  $response = Read-Host -Prompt "$Message (Y/n)"
  if ($response -match '^[Nn]') {
    throw 'Operation cancelled by user.'
  }
}
