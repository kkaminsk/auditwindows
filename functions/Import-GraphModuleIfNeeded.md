# Import-GraphModuleIfNeeded

Loads required Microsoft Graph PowerShell SDK submodules, installing if necessary.

## Parameters

None. Uses script-scope variables `$UseAppAuth` and `$CreateAppIfMissing`.

## Modules Loaded

**Always:**
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Identity.DirectoryManagement`
- `Microsoft.Graph.DeviceManagement`

**When `-UseAppAuth` or `-CreateAppIfMissing`:**
- `Microsoft.Graph.Applications`
- `Microsoft.Graph.ServicePrincipals`

## Behavior

1. Checks if required commands already exist (skips import if so)
2. Installs missing modules to `CurrentUser` scope
3. Falls back to REST via `Invoke-MgGraphRequest` if import fails

## Notes

- Prefers targeted submodules over meta-module to avoid assembly conflicts
- Handles "Assembly already loaded" errors gracefully
