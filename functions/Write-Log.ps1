function Write-Log {
  <#
    .SYNOPSIS
    Writes a timestamped log entry to the audit log file.

    .DESCRIPTION
    Appends a formatted log entry to the script's log file with timestamp and
    severity level. Also outputs to the appropriate PowerShell stream based on
    level (Error, Warning, or Verbose).

    .PARAMETER Message
    The log message text to write.

    .PARAMETER Level
    The severity level: INFO, WARN, ERROR, or DEBUG. Defaults to INFO.

    .EXAMPLE
    Write-Log "Processing device DESKTOP-ABC123" 'INFO'
    Writes: [2025-01-15 10:30:00] INFO: Processing device DESKTOP-ABC123

    .EXAMPLE
    Write-Log "BitLocker lookup failed" 'WARN'
    Writes a warning entry and outputs to Warning stream.

    .NOTES
    Requires $script:logPath to be set before calling.
  #>
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level='INFO'
  )
  $line = ("[{0}] {1}: {2}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message)
  Add-Content -LiteralPath $script:logPath -Value $line
  switch ($Level) {
    'ERROR' { Write-Error $Message }
    'WARN'  { Write-Warning $Message }
    'DEBUG' { Write-Verbose $Message }
    default { Write-Verbose $Message }
  }
}
