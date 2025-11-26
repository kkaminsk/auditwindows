function Add-TextNode {
  <#
    .SYNOPSIS
    Adds a text element to an XML document.

    .DESCRIPTION
    Creates an XML element with the specified name and text content, then appends
    it to the parent element. If the value is null or empty, creates an empty element.

    .PARAMETER xml
    The XML document object to create the element in.

    .PARAMETER parent
    The parent XML element to append the new element to.

    .PARAMETER name
    The name of the XML element to create.

    .PARAMETER value
    The text content for the element. Can be null or empty.

    .EXAMPLE
    Add-TextNode $xml $deviceElement 'Name' 'DESKTOP-ABC123'
    Creates <Name>DESKTOP-ABC123</Name> under the device element.
  #>
  param($xml, $parent, $name, $value)
  $n = $xml.CreateElement($name)
  if ($null -ne $value -and "$value" -ne '') {
    $n.InnerText = [string]$value
  }
  $parent.AppendChild($n) | Out-Null
}
