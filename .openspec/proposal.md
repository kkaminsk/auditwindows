# M-4: Fix Setup script default log path (Documents folder instead of USERPROFILE)

## Problem

`Setup-AuditWindowsApp.ps1` defaults its log/output directory to `$env:USERPROFILE` (e.g., `C:\Users\Kevin`), while `Get-EntraWindowsDevices.ps1` correctly defaults to `[Environment]::GetFolderPath('MyDocuments')` (e.g., `C:\Users\Kevin\Documents`). This inconsistency means:

- Setup logs land in the user profile root, cluttering it
- Audit output goes to Documents — two different locations for related files
- Users expect all output in their Documents folder

## Solution

Change `Setup-AuditWindowsApp.ps1` to use `[Environment]::GetFolderPath('MyDocuments')` as the default output directory, consistent with the main audit script.

## Files Changed

- `Setup-AuditWindowsApp.ps1` — lines 114–115: replace `$env:USERPROFILE` fallback with `[Environment]::GetFolderPath('MyDocuments')`

## Risk

**Low** — Only changes the default path when no explicit `$SummaryOutputPath` is provided. Existing users who pass `-SummaryOutputPath` are unaffected.
