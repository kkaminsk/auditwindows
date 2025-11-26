function Invoke-GraphGetAll {
  param([Parameter(Mandatory=$true)][string]$RelativeUri)
  $uri = "https://graph.microsoft.com/v1.0$RelativeUri"
  $acc = @()
  while ($true) {
    $res = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
    if ($null -ne $res.value) {
      $acc += $res.value
      if ($res.'@odata.nextLink') { $uri = $res.'@odata.nextLink' } else { break }
    } else {
      # not a collection response; return as single-element array
      $acc += $res
      break
    }
  }
  return $acc
}
