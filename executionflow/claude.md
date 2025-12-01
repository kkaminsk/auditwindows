# Execution Flow Documentation

This folder contains detailed execution flow diagrams and phase-by-phase documentation for the Audit Windows scripts.

## Purpose

These documents describe **what happens when** during script execution, providing:
- Step-by-step execution phases with line number references
- Graph API calls and their purposes
- Decision flowcharts and diagrams
- Parameter references
- Error handling behavior
- Output file schemas

## Contents

| File | Documents |
|------|-----------|
| `Setup-AuditWindowsApp_ExecutionFlow.md` | App registration setup (10 phases) |
| `Get-EntraWindowsDevices_ExecutionFlow.md` | Device audit execution (7 phases) |

## When to Use These Docs

- Understanding the script flow before making changes
- Debugging issues at specific execution points
- Reviewing Graph API usage and required permissions
- Understanding authentication paths and certificate handling

## Documentation Standards

When updating these files:

1. **Keep line number references current** - Update `Lines: X-Y` when source scripts change
2. **Maintain phase structure** - Each phase should have:
   - Phase number and title
   - Line number range
   - Function name (if applicable)
   - Step-by-step table with Action and Details/Graph API columns
3. **Update flow diagrams** - ASCII diagrams should reflect current logic
4. **Document all parameters** - Include type, default, and description
5. **List Graph API calls** - Include endpoint, method, and purpose

## Related Documentation

- `../functions/*.md` - Individual function documentation
- `../CLAUDE.md` - Project-level coding standards
- `../README.md` - User-facing documentation
