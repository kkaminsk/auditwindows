# Security Remediation Spec

## S-1: Prevent Sensitive Data in Repository

**GIVEN** the repository has no `.gitignore`  
**WHEN** a user runs Setup-AuditWindowsApp.ps1 from the repo directory  
**THEN** log files, certificate exports, and JSON summaries are committed to source control  

**GIVEN** a `.gitignore` is added with patterns for `*.log`, `*.cer`, `*.pfx`, `*.json` output files  
**WHEN** a user runs any script from the repo directory  
**THEN** sensitive output files are excluded from git tracking  

## S-2: OData Filter Injection Prevention

**GIVEN** a device name contains a single quote (e.g., `O'Brien's PC`)  
**WHEN** the device name is used in an OData filter like `displayName eq '$deviceName'`  
**THEN** the query fails or returns unexpected results  

**GIVEN** single quotes in filter values are escaped by doubling (`''`)  
**WHEN** the same device name is used in an OData filter  
**THEN** the query correctly filters by the exact device name  

## S-3: Log Path Safety

**GIVEN** `Write-Log` is called before `$script:logPath` is initialized  
**WHEN** the function attempts to write to the log file  
**THEN** it should silently skip writing instead of throwing an error  

**GIVEN** `Setup-AuditWindowsApp.ps1` is run from the repository directory  
**WHEN** no `-SummaryOutputPath` is specified  
**THEN** log files should be written to `$env:USERPROFILE` not `$PSScriptRoot`  
