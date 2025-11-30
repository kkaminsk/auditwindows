function Read-AuditWindowsYesNo {
  <#
    .SYNOPSIS
    Prompts for a yes/no response with input validation.
    .PARAMETER Prompt
    The prompt message to display.
    .PARAMETER Default
    The default value if the user presses Enter. Must be 'Y' or 'N'.
    .OUTPUTS
    Returns $true for yes, $false for no.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Prompt,
    [ValidateSet('Y', 'N')]
    [string]$Default
  )

  $hint = if ($Default -eq 'Y') { '(Y/n)' } elseif ($Default -eq 'N') { '(y/N)' } else { '(y/n)' }

  while ($true) {
    $response = Read-Host -Prompt "$Prompt $hint"
    if ($null -eq $response) {
      $response = ''
    }
    $response = $response.Trim().ToUpper()

    if ([string]::IsNullOrEmpty($response)) {
      if ($Default) {
        return $Default -eq 'Y'
      }
      Write-Host "Please enter 'y' or 'n'." -ForegroundColor Yellow
      continue
    }

    if ($response -eq 'Y' -or $response -eq 'YES') {
      return $true
    }
    if ($response -eq 'N' -or $response -eq 'NO') {
      return $false
    }

    Write-Host "Invalid input '$response'. Please enter 'y' or 'n'." -ForegroundColor Yellow
  }
}
