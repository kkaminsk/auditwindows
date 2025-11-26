function New-AuditXml {
  $xml = New-Object System.Xml.XmlDocument
  $decl = $xml.CreateXmlDeclaration('1.0','UTF-8',$null)
  $xml.AppendChild($decl) | Out-Null
  $root = $xml.CreateElement('WindowsAudit')
  $xml.AppendChild($root) | Out-Null
  return $xml
}
