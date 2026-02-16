# M-4: Setup Script Default Log Path — Specifications

## Scenario 1: Default log path without SummaryOutputPath

**GIVEN** the user runs `Setup-AuditWindowsApp.ps1` without `-SummaryOutputPath`
**WHEN** the script initializes output paths
**THEN** logs and JSON output are written to `[Environment]::GetFolderPath('MyDocuments')`

## Scenario 2: Explicit SummaryOutputPath overrides default

**GIVEN** the user runs `Setup-AuditWindowsApp.ps1` with `-SummaryOutputPath C:\Custom\output.json`
**WHEN** the script initializes output paths
**THEN** logs and JSON output are written to `C:\Custom\`

## Scenario 3: Documents folder is created if missing

**GIVEN** the resolved Documents folder does not exist
**WHEN** the script initializes output paths
**THEN** the directory is created before writing any logs
