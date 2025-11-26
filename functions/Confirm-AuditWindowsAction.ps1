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

  $response = Read-Host -Prompt "$Message (y/N)"
  if ($response -notmatch '^[Yy]') {
    throw 'Operation cancelled by user.'
  }
}
