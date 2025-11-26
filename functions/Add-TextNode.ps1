function Add-TextNode {
  param($xml, $parent, $name, $value)
  $n = $xml.CreateElement($name)
  if ($null -ne $value -and "$value" -ne '') {
    $n.InnerText = [string]$value
  }
  $parent.AppendChild($n) | Out-Null
}
