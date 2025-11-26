function Confirm-AuditWindowsAction {
  <#
    .SYNOPSIS
    Prompts for confirmation before proceeding with an action.

    .DESCRIPTION
    Displays a confirmation prompt with the specified message and waits for user input.
    The default action is Yes (pressing Enter proceeds). Only typing 'n' or 'N' cancels
    the operation. If -Force is specified, the prompt is skipped entirely.

    .PARAMETER Message
    The confirmation message to display to the user.

    .PARAMETER Force
    If specified, skips the confirmation prompt and proceeds automatically.

    .EXAMPLE
    Confirm-AuditWindowsAction -Message "Proceed with app registration?"
    Displays: "Proceed with app registration? (Y/n)" - Enter proceeds, 'n' cancels.

    .EXAMPLE
    Confirm-AuditWindowsAction -Message "Delete resource?" -Force
    Skips the prompt and proceeds without user interaction.

    .NOTES
    Throws an exception with message 'Operation cancelled by user.' if the user types 'n' or 'N'.
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
