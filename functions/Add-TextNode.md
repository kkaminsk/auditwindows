# Add-TextNode

Adds a text element to an XML parent node.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `xml` | XmlDocument | Yes | The XML document |
| `parent` | XmlElement | Yes | Parent element to append to |
| `name` | string | Yes | Element name |
| `value` | any | No | Text content (empty if null) |

## Example

```powershell
$xml = New-AuditXml
$device = $xml.CreateElement('Device')
$xml.DocumentElement.AppendChild($device)

Add-TextNode $xml $device 'Name' 'DESKTOP-ABC'
Add-TextNode $xml $device 'Enabled' 'true'
```

Produces:
```xml
<Device>
  <Name>DESKTOP-ABC</Name>
  <Enabled>true</Enabled>
</Device>
```
