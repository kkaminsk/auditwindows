# Code Audit Report

**Date:** 2026-02-16  
**Auditor:** Automated Code Audit (OpenClaw)  
**Scope:** Full codebase review of auditwindows repository

---

## Executive Summary

The auditwindows project is a well-structured PowerShell 7 tool with strong security fundamentals. This audit identified **3 High**, **6 Medium**, and **5 Low** severity findings. The most critical issues are committed log files containing tenant IDs, missing `.gitignore`, and OData filter injection risks.

---

## High Severity

### H-1: Committed Log Files Contain Sensitive Data

**Files:**
- `Setup-AuditWindowsApp-2025-11-30-16-02.log`
- `Setup-AuditWindowsApp-2025-11-30-16-41.log`

**Finding:** Both log files contain the Azure AD tenant ID (`5a01497e-1bcb-4711-b6e6-d24f4ab00393`). While tenant IDs are not secrets per se, they are organizational identifiers that should not be in public repositories. Log files may also contain usernames, app IDs, and other operational data in future runs.

**Remediation:** Remove log files from repository, add to `.gitignore`.

### H-2: No .gitignore File

**Finding:** The repository has no `.gitignore` file at all. This means log files (`*.log`), certificate exports (`.cer`, `.pfx`), JSON summaries with app/tenant IDs, and XML/CSV audit output could all be accidentally committed.

**Remediation:** Create comprehensive `.gitignore`.

### H-3: OData Filter Injection in Graph Queries

**Files:** Multiple functions use string interpolation in OData filters:
- `Get-AuditWindowsApplication.ps1`: `"displayName eq '$DisplayName'"`
- `Connect-GraphInteractive.ps1`: `"displayName eq '$appName'"`
- `Test-LapsAvailable.ps1`: `"deviceName eq '$deviceName'"`
- `Get-BitLockerKeysByDeviceId.ps1`: `"deviceId eq '$azureId'"`
- `Get-ManagedDeviceByAadId.ps1`: `"azureADDeviceId eq '$azureId'"`

**Finding:** If any input contains a single quote (`'`), the OData filter breaks or could be manipulated. While these values come from trusted sources (Graph API results, user parameters), it's a defense-in-depth gap. Device names in particular can contain special characters.

**Remediation:** Sanitize single quotes by doubling them (`$value -replace "'", "''"`) in OData filter values.

---

## Medium Severity

### M-1: `Write-Log` Requires Uninitialized `$script:logPath`

**File:** `functions/Write-Log.ps1`

**Finding:** `Write-Log` uses `$script:logPath` which must be set before calling. If called before initialization (e.g., during module import errors), it will fail silently or throw. The `Setup-AuditWindowsApp.ps1` script defines its own `Write-SetupLog` function instead of reusing `Write-Log`, creating duplication.

**Remediation:** Add a guard clause to `Write-Log` that checks if `$script:logPath` is set.

### M-2: Duplicate Logging Functions

**Files:**
- `functions/Write-Log.ps1` — used by `Get-EntraWindowsDevices.ps1`
- `Setup-AuditWindowsApp.ps1` lines ~75-85 — defines `Write-SetupLog` inline

**Finding:** Two separate logging implementations with slightly different formats. `Write-Log` uses `[timestamp] LEVEL: message`, `Write-SetupLog` uses `[timestamp] [LEVEL] message`.

**Remediation:** Consolidate into a single `Write-Log` function. Setup script should use the same function.

### M-3: `Invoke-GraphGetAll` Unbounded Memory Accumulation

**File:** `functions/Invoke-GraphGetAll.ps1`

**Finding:** Results are accumulated in `$acc += $res.value` using array concatenation in a loop. For tenants with thousands of devices, this is O(n²) due to PowerShell array immutability. Should use `[System.Collections.Generic.List[object]]`.

**Remediation:** Replace `$acc = @()` / `$acc +=` with a `List[object]` and `.AddRange()`.

### M-4: Setup Script Generates Logs in Script Directory

**File:** `Setup-AuditWindowsApp.ps1` line ~68

**Finding:** `$script:logPath` defaults to `$PSScriptRoot` (the repo directory), which means running the setup script from the repo creates log files in the repo. This is how the committed log files (H-1) were created.

**Remediation:** Default log output to `$env:USERPROFILE` or a temp directory, not `$PSScriptRoot`.

### M-5: Missing `[CmdletBinding()]` on Several Functions

**Files:** `Add-TextNode.ps1`, `Get-BitLockerKeysByDeviceId.ps1`, `Get-ManagedDeviceByAadId.ps1`, `Get-WindowsDirectoryDevices.ps1`, `Test-LapsAvailable.ps1`, `New-AuditXml.ps1`, `Invoke-GraphGet.ps1`, `Invoke-GraphGetAll.ps1`, `Import-GraphModuleIfNeeded.ps1`, `Connect-GraphInteractive.ps1`

**Finding:** These functions lack `[CmdletBinding()]` attribute, preventing use of common parameters like `-Verbose`, `-ErrorAction`, etc.

**Remediation:** Add `[CmdletBinding()]` to all functions.

### M-6: `Get-EntraWindowsDevices.ps1` Main Script Has Dense Inline XML Construction

**File:** `Get-EntraWindowsDevices.ps1` lines ~115-125

**Finding:** The BitLocker XML construction is a series of chained statements on single lines that are very hard to read and maintain. This increases the risk of bugs during modifications.

**Remediation:** Refactor into a helper function or at minimum break into readable multi-line statements.

---

## Low Severity

### L-1: README Contains Broken Unicode Characters

**File:** `README.md`

**Finding:** Multiple instances of corrupted Unicode characters (e.g., `—` appearing as `â€"`, `'` as `â€™`). This is an encoding issue from editing in different editors.

**Remediation:** Fix encoding to UTF-8 and replace corrupted characters.

### L-2: SecurityAudit.md References Pre-Implementation State

**File:** `SecurityAudit.md`

**Finding:** The security audit document (dated 2025-11-30) recommends implementing features that have since been implemented (Key Vault integration, non-exportable certificates, certificate health monitoring). The document is now misleading.

**Remediation:** Update or archive the document to reflect current state.

### L-3: Inconsistent Parameter Naming Between Scripts

**Finding:**
- `Setup-AuditWindowsApp.ps1` uses `-CertificateStoreLocation`
- `Get-EntraWindowsDevices.ps1` uses `-CertSubject` (abbreviated)
- `Setup-AuditWindowsApp.ps1` uses `-AppDisplayName`
- `Get-EntraWindowsDevices.ps1` uses both `-AppName` and `-AppDisplayName`

**Remediation:** Document the parameter mapping clearly; consider aliases for consistency.

### L-4: `Get-KeyVaultCertificateLocal.ps1` Duplicates Logic

**File:** `Get-KeyVaultCertificateLocal.ps1`

**Finding:** This standalone script duplicates certificate download logic that exists in `Get-AuditWindowsKeyVaultCertificate`. The interactive Key Vault browsing UI (subscription → RG → vault → cert selection) is ~200 lines that could be extracted into reusable functions.

**Remediation:** Extract interactive selection into shared functions.

### L-5: No Pester Tests

**Finding:** The project has no automated tests. Given the complexity of Graph API interactions and certificate management, at minimum unit tests for utility functions (`Add-TextNode`, `ConvertTo-AuditWindowsThumbprintString`, `Invoke-GraphWithRetry` retry logic) would catch regressions.

**Remediation:** Add Pester test scaffolding for utility functions.

---

## Summary

| Severity | Count | Key Themes |
|----------|-------|------------|
| High     | 3     | Committed secrets, missing gitignore, injection risk |
| Medium   | 6     | Code quality, performance, duplicate code |
| Low      | 5     | Documentation, naming, testing |

