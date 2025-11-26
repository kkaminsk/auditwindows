function Write-Log {
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
