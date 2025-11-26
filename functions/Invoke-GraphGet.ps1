function Invoke-GraphGet {
  param([Parameter(Mandatory=$true)][string]$RelativeUri)
  $uri = "https://graph.microsoft.com/v1.0$RelativeUri"
  Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
}
