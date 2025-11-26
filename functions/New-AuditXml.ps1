function New-AuditXml {
  <#
    .SYNOPSIS
    Creates a new XML document for the Windows audit report.

    .DESCRIPTION
    Initializes an XML document with UTF-8 encoding declaration and a
    <WindowsAudit> root element. Used as the container for device audit data.

    .OUTPUTS
    System.Xml.XmlDocument with structure:
    <?xml version="1.0" encoding="UTF-8"?>
    <WindowsAudit></WindowsAudit>

    .EXAMPLE
    $xml = New-AuditXml
    $root = $xml.DocumentElement
    Creates a new audit XML document and gets the root element.
  #>
  $xml = New-Object System.Xml.XmlDocument
  $decl = $xml.CreateXmlDeclaration('1.0','UTF-8',$null)
  $xml.AppendChild($decl) | Out-Null
  $root = $xml.CreateElement('WindowsAudit')
  $xml.AppendChild($root) | Out-Null
  return $xml
}
