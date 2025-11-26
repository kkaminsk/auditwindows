# New-AuditXml

Creates a new XML document for the Windows audit report.

## Parameters

None.

## Returns

`System.Xml.XmlDocument` with:
- UTF-8 XML declaration
- Root element `<WindowsAudit>`

## Example

```powershell
$xml = New-AuditXml
$root = $xml.DocumentElement
# Add device elements to $root
$xml.Save('C:\Reports\audit.xml')
```
