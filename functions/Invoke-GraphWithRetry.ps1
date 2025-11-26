function Invoke-GraphWithRetry {
  param(
    [scriptblock]$Script,
    [int]$MaxRetries=4,
    [string]$OperationName,
    [string]$Resource,
    [int[]]$NonFatalStatusCodes,
    $NonFatalReturn
  )
  $i=0
  while ($true) {
    if ($OperationName -or $Resource) { Write-Log "Graph call attempt $($i+1): op='$OperationName' resource='$Resource'" 'DEBUG' }
    $startAttempt = Get-Date
    try {
      $result = & $Script
      $elapsed = [int]((Get-Date) - $startAttempt).TotalMilliseconds
      if ($OperationName -or $Resource) { Write-Log "Graph call success: op='$OperationName' resource='$Resource' elapsedMs=$elapsed" 'DEBUG' }
      return $result
    } catch {
      $msg=$_.Exception.Message
      $code=$null; try { if ($_.Exception.Response.StatusCode) { $code=[int]$_.Exception.Response.StatusCode } } catch {}
      # Try to parse Status: 404 from the message text emitted by Graph cmdlets
      if (-not $code) { try { $m=[regex]::Match($msg,'Status:\s*(\d{3})'); if ($m.Success) { $code = [int]$m.Groups[1].Value } } catch {} }
      # If still no code but message indicates not found and caller treats 404 as non-fatal, honor that
      if (-not $code -and $NonFatalStatusCodes -and ($NonFatalStatusCodes -contains 404) -and ($msg -match '(?i)\bnot\s*found\b|\bcould not be found\b')) { $code = 404 }
      if ($NonFatalStatusCodes -and ($code -in $NonFatalStatusCodes)) {
        Write-Log "Graph call non-fatal (status=$code) op='$OperationName' resource='$Resource': $msg" 'DEBUG'
        return $NonFatalReturn
      }
      $retry=$code -in 429,502,503,504 -or $msg -match 'timeout|temporar|Too Many'
      $i++
      $wait=[Math]::Min(2*[Math]::Pow(2,$i),60)
      try {
        $headers = $_.Exception.Response.Headers
        if ($headers -and $headers['Retry-After']) { $wait = [int]$headers['Retry-After'] }
      } catch {}
      if ($i -le $MaxRetries -and $retry) {
        Write-Log "Graph call retry $i/$MaxRetries in $wait sec (status=$code) op='$OperationName' resource='$Resource' msg: $msg" 'WARN'
        Start-Sleep -Seconds $wait
        continue
      }
      Write-Log "Graph call failed (status=$code) op='$OperationName' resource='$Resource': $msg" 'ERROR'
      throw
    }
  }
}
