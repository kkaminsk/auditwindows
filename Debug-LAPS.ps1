#Requires -Version 7.0
$deviceId = "b10327c7-7158-4828-848c-969590feb8d8"

Write-Host "=== LAPS Detection Debugging ===" -ForegroundColor Cyan
Write-Host "Device ID: $deviceId`n"

# Ensure connected
try {
    $ctx = Get-MgContext
    if (-not $ctx) {
        Write-Host "Connecting to Graph..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes 'Device.Read.All','DeviceLocalCredential.ReadBasic.All' -NoWelcome
    }
} catch {
    Write-Host "Connecting to Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes 'Device.Read.All','DeviceLocalCredential.ReadBasic.All' -NoWelcome
}

Write-Host "`n1. Testing Get-LapsAADPassword (known working):" -ForegroundColor Green
try {
    $lapsCmd = Get-LapsAADPassword -DeviceIds $deviceId
    Write-Host "   SUCCESS - Password found" -ForegroundColor Green
    $lapsCmd | Format-List DeviceName, DeviceId, PasswordExpirationTime
} catch {
    Write-Host "   FAILED: $_" -ForegroundColor Red
}

Write-Host "`n2. Testing direct Graph query with filter:" -ForegroundColor Green
$uri = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials?`$filter=deviceId eq '$deviceId'"
Write-Host "   URI: $uri"
try {
    $result = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject
    Write-Host "   Response received" -ForegroundColor Green
    Write-Host "   - @odata.context: $($result.'@odata.context')"
    Write-Host "   - value exists: $($null -ne $result.value)"
    Write-Host "   - value type: $($result.value.GetType().Name)"
    Write-Host "   - value.Count: $($result.value.Count)"
    
    if ($result.value -and $result.value.Count -gt 0) {
        Write-Host "   CREDENTIALS FOUND:" -ForegroundColor Green
        $result.value | ForEach-Object {
            Write-Host "     - id: $($_.id)"
            Write-Host "       deviceId: $($_.deviceId)"
            Write-Host "       deviceName: $($_.deviceName)"
            Write-Host "       lastBackupDateTime: $($_.lastBackupDateTime)"
        }
    } else {
        Write-Host "   NO CREDENTIALS (empty value array)" -ForegroundColor Red
    }
    
    Write-Host "`n   Test condition: `$result -and `$result.value -and `$result.value.Count -gt 0"
    Write-Host "   Result: $($result -and $result.value -and $result.value.Count -gt 0)" -ForegroundColor $(if ($result -and $result.value -and $result.value.Count -gt 0) { 'Green' } else { 'Red' })
} catch {
    Write-Host "   FAILED: $_" -ForegroundColor Red
    Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

Write-Host "`n3. Testing query WITHOUT filter (first 5 results):" -ForegroundColor Green
$uri2 = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials?`$top=5"
try {
    $result2 = Invoke-MgGraphRequest -Method GET -Uri $uri2 -OutputType PSObject
    Write-Host "   Found $($result2.value.Count) credentials total" -ForegroundColor Green
    $result2.value | Select-Object -First 3 | ForEach-Object {
        Write-Host "     - deviceId: $($_.deviceId), deviceName: $($_.deviceName)"
    }
    
    # Check if our device is in there
    $match = $result2.value | Where-Object { $_.deviceId -eq $deviceId }
    if ($match) {
        Write-Host "   OUR DEVICE IS IN THE COLLECTION!" -ForegroundColor Green
    } else {
        Write-Host "   Our device NOT in first 5 results (may need pagination)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   FAILED: $_" -ForegroundColor Red
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "If Get-LapsAADPassword works but the Graph query doesn't,"
Write-Host "there may be an issue with filter syntax or API permissions."
