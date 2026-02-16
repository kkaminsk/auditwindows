function Protect-ODataFilterValue {
  <#
    .SYNOPSIS
    Escapes a string value for safe use in OData filter expressions.

    .DESCRIPTION
    Doubles single quotes in the input string to prevent OData filter injection.
    OData uses single quotes to delimit string values, so any embedded single
    quotes must be escaped by doubling them.

    .PARAMETER Value
    The string value to escape.

    .OUTPUTS
    System.String. The escaped string safe for OData filter use.

    .EXAMPLE
    $safe = Protect-ODataFilterValue "O'Brien's PC"
    # Returns: O''Brien''s PC
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Value
  )
  return $Value -replace "'", "''"
}
