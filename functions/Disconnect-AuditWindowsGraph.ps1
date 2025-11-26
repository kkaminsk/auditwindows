function Disconnect-AuditWindowsGraph {
  <#
    .SYNOPSIS
    Disconnects from Microsoft Graph and cleans up the session.

    .DESCRIPTION
    Safely terminates the current Microsoft Graph session. Checks if a session exists
    before attempting to disconnect and silently handles any errors during disconnection.
    Called at the end of Setup-AuditWindowsApp.ps1 to ensure clean session management.

    .EXAMPLE
    Disconnect-AuditWindowsGraph
    Disconnects from the current Microsoft Graph session if one exists.

    .NOTES
    This function is safe to call even if no session exists - it will silently return.
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
