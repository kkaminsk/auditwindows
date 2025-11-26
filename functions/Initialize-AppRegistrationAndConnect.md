# Initialize-AppRegistrationAndConnect

Provisions app registration and connects with certificate auth (legacy inline provisioning).

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Tenant` | string | Yes | - | Tenant ID |
| `Name` | string | No | `WindowsAuditApp` | App display name |
| `Create` | switch | No | - | Create app if missing |
| `Subject` | string | No | `CN=$Name` | Certificate subject |

## Behavior (with `-Create`)

1. Connects with admin scopes (device code)
2. Creates/finds application registration
3. Creates/finds service principal
4. Creates/finds certificate in `Cert:\CurrentUser\My`
5. Adds certificate to app keyCredentials
6. Grants Graph application permissions
7. Connects app-only with certificate

## Behavior (without `-Create`)

1. Finds existing certificate by subject
2. Finds existing application by name
3. Connects app-only with certificate

## Used By

`Get-EntraWindowsDevices.ps1 -UseAppAuth -CreateAppIfMissing`

## Notes

For new deployments, prefer `Setup-AuditWindowsApp.ps1` which uses the modular setup functions.
