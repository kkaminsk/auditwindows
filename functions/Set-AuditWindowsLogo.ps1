function Set-AuditWindowsLogo {
  <#
    .SYNOPSIS
    Uploads a logo to the Audit Windows application if logo.jpg exists.
    .OUTPUTS
    Returns $true if logo was uploaded, $false otherwise.
  #>
  param(
    [Parameter(Mandatory)]
    $Application,
    [Parameter(Mandatory)]
    [string]$ScriptRoot
  )

  $logoPath = Join-Path -Path $ScriptRoot -ChildPath 'logo.jpg'

  if (-not (Test-Path -Path $logoPath)) {
    Write-Warning "Logo file not found at $logoPath. Place logo.jpg next to Setup-AuditWindowsApp.ps1 to upload branding."
    Write-Warning 'Audit Windows application will continue with default icon.'
    return $false
  }

  try {
    $logoInfo = Get-Item -Path $logoPath
    Write-Host "Uploading application logo from $logoPath ($([Math]::Round($logoInfo.Length / 1KB, 2)) KB)..." -ForegroundColor Cyan
    Set-MgApplicationLogo -ApplicationId $Application.Id -InFile $logoPath -ErrorAction Stop
    Write-Host 'Application logo uploaded successfully.' -ForegroundColor Green
    return $true
  }
  catch {
    Write-Warning "Failed to upload application logo: $($_.Exception.Message)"
    Write-Warning 'Ensure the file is a JPEG under 100 KB, then rerun the script or update the logo manually in Entra Portal.'
    return $false
  }
}
