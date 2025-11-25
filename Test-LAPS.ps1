$deviceName = Read-Host "Enter the device name you want to check"
Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes 'Device.Read.All','DeviceLocalCredential.ReadBasic.All' -NoWelcome

Write-Host "`nQuerying device: $deviceName" -ForegroundColor Cyan
# Use REST to avoid module import issues
$filter = "displayName eq '$deviceName'"
$devicesResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=$filter" -OutputType PSObject
$dev = $devicesResponse.value | Select-Object -First 1

if (-not $dev) {
    Write-Host "Device not found in Entra ID" -ForegroundColor Red
    exit 1
}

Write-Host "Found device:" -ForegroundColor Green
Write-Host "  DisplayName: $($dev.DisplayName)"
Write-Host "  ObjectId: $($dev.Id)"
Write-Host "  DeviceId (Azure AD): $($dev.DeviceId)"

Write-Host "`nChecking LAPS credentials via /devices/$($dev.Id)/localCredentials..." -ForegroundColor Cyan
try {
    $lapsResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/devices/$($dev.Id)/localCredentials" -OutputType PSObject
    
    if ($lapsResponse.value -and $lapsResponse.value.Count -gt 0) {
        Write-Host "LAPS credentials FOUND: $($lapsResponse.value.Count) credential(s)" -ForegroundColor Green
        $lapsResponse.value | ForEach-Object {
            Write-Host "  - ID: $($_.id)"
            Write-Host "    DeviceId: $($_.deviceId)"
            Write-Host "    LastBackupDateTime: $($_.lastBackupDateTime)"
        }
    } else {
        Write-Host "LAPS credentials NOT FOUND (empty collection)" -ForegroundColor Yellow
    }
} catch {
    $statusCode = $null
    if ($_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    
    if ($statusCode -eq 404) {
        Write-Host "LAPS credentials NOT FOUND (404 Not Found)" -ForegroundColor Yellow
    } else {
        Write-Host "Error checking LAPS: $_" -ForegroundColor Red
        Write-Host "Status code: $statusCode" -ForegroundColor Red
    }
}

Write-Host "`nNow run the script with -DeviceName to compare:" -ForegroundColor Cyan
Write-Host "  .\Get-EntraWindowsDevices.ps1 -DeviceName '$deviceName' -ExportCSV -Verbose" -ForegroundColor White