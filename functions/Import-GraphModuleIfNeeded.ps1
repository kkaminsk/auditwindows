function Import-GraphModuleIfNeeded {
  # Prefer targeted submodules to avoid meta-module assembly conflicts
  # Note: InformationProtection module may not exist in all SDK versions; REST fallback handles this
  $neededModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Identity.DirectoryManagement',
    'Microsoft.Graph.DeviceManagement'
  )
  # Only load app management modules when app-only auth/provisioning is requested
  if ($script:UseAppAuth -or $script:CreateAppIfMissing) {
    $neededModules += @('Microsoft.Graph.Applications','Microsoft.Graph.ServicePrincipals')
  }
  $cmdChecks = @{
    'Microsoft.Graph.Authentication'               = @('Connect-MgGraph','Get-MgContext','Invoke-MgGraphRequest')
    'Microsoft.Graph.Applications'                 = @('New-MgApplication','Update-MgApplication','Get-MgApplication')
    'Microsoft.Graph.ServicePrincipals'            = @('New-MgServicePrincipal','Get-MgServicePrincipal','New-MgServicePrincipalAppRoleAssignment','Get-MgServicePrincipalAppRoleAssignment')
    'Microsoft.Graph.Identity.DirectoryManagement' = @('Get-MgDevice','Get-MgDirectoryDeviceLocalCredential')
    'Microsoft.Graph.DeviceManagement'             = @('Get-MgDeviceManagementManagedDevice')
    'Microsoft.Graph.InformationProtection'        = @('Get-MgInformationProtectionBitlockerRecoveryKey')
  }
  # First, check if all required commands are already available
  $allCmdsPresent = $true
  foreach ($m in $neededModules) {
    $checks = $cmdChecks[$m]
    if ($checks) {
      $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
      if ($missing.Count -gt 0) {
        $allCmdsPresent = $false
        break
      }
    }
  }
  if ($allCmdsPresent) {
    Write-Log "All required Graph commands already available; skipping module imports." 'INFO'
    Write-Host "All required Graph commands already available; skipping module imports."
    return
  }
  foreach ($m in $neededModules) {
    $checks = $cmdChecks[$m]
    if ($checks) {
      $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
      if ($missing.Count -eq 0) {
        Write-Log ("Commands already available for {0}; skipping import." -f $m) 'INFO'
        Write-Host ("Commands already available for {0}; skipping import." -f $m)
        continue
      }
    }
    if (-not (Get-Module -ListAvailable -Name $m)) {
      Write-Log ("Installing {0} to CurrentUser..." -f $m) 'WARN'
      try {
        Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
      } catch {
        Write-Log ("Install failed for {0}: {1}. REST fallback will be used." -f $m, $_) 'WARN'
        Write-Host ("Could not install {0}; will use REST fallback." -f $m) -ForegroundColor Yellow
        continue
      }
    }
    Write-Host ("Loading module: {0}" -f $m)
    try {
      Import-Module $m -ErrorAction Stop
      $loaded = Get-Module -Name $m | Select-Object -First 1
      if ($loaded) { Write-Log ("Loaded {0} v{1} from {2}" -f $loaded.Name, $loaded.Version, $loaded.Path) 'INFO' }
    } catch {
      $errText = $_.ToString()
      Write-Log ("Failed to import {0}: {1}" -f $m, $errText) 'WARN'
      # If assemblies are already loaded but commands are present, proceed
      if ($errText -match 'Assembly with same name is already loaded') {
        $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($missing.Count -eq 0) {
          Write-Log ("Assembly already loaded for {0}; required commands present. Proceeding." -f $m) 'WARN'
          Write-Host ("Assembly already loaded for {0}; required commands present. Proceeding." -f $m)
          continue
        }
      }
      Write-Host ("Import issue for {0}. Attempting import by explicit path..." -f $m) -ForegroundColor Yellow
      $latest = Get-Module -ListAvailable -Name $m | Sort-Object Version -Descending | Select-Object -First 1
      if ($latest) {
        try {
          Import-Module -FullyQualifiedName $latest.Path -ErrorAction Stop
          Write-Log ("Imported {0} by path: {1}" -f $m, $latest.Path) 'INFO'
        } catch {
          $errText2 = $_.ToString()
          Write-Log ("Import by path failed for {0}: {1}" -f $m, $errText2) 'WARN'
          # Final fallback: if commands exist anyway, proceed; else warn and continue (REST fallback will handle it)
          $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
          if ($missing.Count -eq 0) {
            Write-Log ("Commands detected despite import error for {0}. Proceeding." -f $m) 'WARN'
            Write-Host ("Commands detected despite import error for {0}. Proceeding." -f $m)
          } else {
            Write-Log ("Import failed for {0} but REST fallback available. Proceeding." -f $m) 'WARN'
            Write-Host ("Import failed for {0}; will use REST fallback." -f $m) -ForegroundColor Yellow
          }
        }
      } else {
        # No module found; if commands exist (from previous meta-module), proceed
        $missing = @($checks | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($missing.Count -eq 0) {
          Write-Log ("No installable module found for {0}, but commands are present. Proceeding." -f $m) 'WARN'
          Write-Host ("No installable module found for {0}, but commands are present. Proceeding." -f $m)
        } else {
          Write-Log ("No module found for {0} but REST fallback available. Proceeding." -f $m) 'WARN'
          Write-Host ("No module found for {0}; will use REST fallback." -f $m) -ForegroundColor Yellow
        }
      }
    }
  }
  Write-Log "Graph submodules loaded." 'INFO'
  Write-Host "Graph submodules loaded."
}
