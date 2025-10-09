#Requires -Version 7.0

Write-Host "=== Finding correct LAPS property names ===" -ForegroundColor Cyan

# Get all credentials without filter
$uri = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials?`$top=10"
$result = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject

Write-Host "`nFound $($result.value.Count) credentials"
Write-Host "`nFirst credential's properties:" -ForegroundColor Yellow
$first = $result.value[0]
$first.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Value)"
}

Write-Host "`nLooking for our device (DESKTOP-KIJL01G):" -ForegroundColor Yellow
$ourDevice = $result.value | Where-Object { $_.deviceName -eq 'DESKTOP-KIJL01G' }
if ($ourDevice) {
    Write-Host "  FOUND!" -ForegroundColor Green
    Write-Host "`nAll properties for DESKTOP-KIJL01G:" -ForegroundColor Cyan
    $ourDevice.PSObject.Properties | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Value)"
    }
} else {
    Write-Host "  Not in first 10 results" -ForegroundColor Yellow
}

Write-Host "`nTesting filter by 'id' property:" -ForegroundColor Cyan
if ($ourDevice) {
    $testUri = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials?`$filter=id eq '$($ourDevice.id)'"
    Write-Host "  URI: $testUri"
    try {
        $testResult = Invoke-MgGraphRequest -Method GET -Uri $testUri -OutputType PSObject
        Write-Host "  SUCCESS - Found $($testResult.value.Count) credential(s)" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nTesting filter by 'deviceName' property:" -ForegroundColor Cyan
$testUri2 = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials?`$filter=deviceName eq 'DESKTOP-KIJL01G'"
Write-Host "  URI: $testUri2"
try {
    $testResult2 = Invoke-MgGraphRequest -Method GET -Uri $testUri2 -OutputType PSObject
    Write-Host "  SUCCESS - Found $($testResult2.value.Count) credential(s)" -ForegroundColor Green
    if ($testResult2.value.Count -gt 0) {
        Write-Host "  THIS FILTER WORKS! Use deviceName instead of deviceId" -ForegroundColor Green
    }
} catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
