function Disconnect-AuditWindowsGraph {
  <#
    .SYNOPSIS
    Disconnects from Microsoft Graph and cleans up the session.
  #>
  [CmdletBinding()]
  param()

  try {
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if ($context) {
      Write-Host "Disconnecting from Microsoft Graph..." -ForegroundColor Cyan
      Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
      Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    }
  }
  catch {
    # Silently ignore disconnect errors
  }
}
