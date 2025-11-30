## Context

The Audit Windows tool uses certificate-based authentication for app-only (unattended) scenarios. Currently, certificates are stored in the Windows Certificate Store (`Cert:\CurrentUser\My`) with exportable private keys. While functional, this approach has security limitations identified in the Security Audit:

- Private keys can be exported by any process running under the same user context
- Lost/stolen workstations expose certificate private keys
- No hardware-backed key protection

This change introduces multiple hardening options to address different security requirements and operational constraints.

## Goals / Non-Goals

### Goals
- Provide a "quick win" non-exportable certificate option requiring no additional infrastructure
- Support Azure Key Vault for centralized, HSM-backed certificate storage
- Add certificate health monitoring to prevent silent authentication failures
- Maintain backward compatibility with existing deployments

### Non-Goals
- Hardware token/smart card/TPM support (future enhancement, high complexity)
- Mandatory migration of existing certificates (opt-in hardening)
- Automatic certificate rotation (manual rotation supported)

## Decisions

### Decision 1: Non-Exportable Certificates as Default Recommendation

**What:** Add `-NonExportable` switch that creates certificates with `KeyExportPolicy NonExportable`.

**Why:**
- Zero additional infrastructure required
- Immediate security improvement
- Trade-off (no backup/migration) acceptable for most scenarios since setup script can regenerate

**Alternatives Considered:**
- Make non-exportable the default: Rejected because it would break existing workflows expecting PFX export
- Remove exportable option entirely: Rejected for backward compatibility

### Decision 2: Azure Key Vault as Production Recommendation

**What:** Add `-UseKeyVault` parameter set to retrieve or create certificates in Azure Key Vault.

**Why:**
- Centralized secret management
- Optional HSM backing (`az keyvault create --sku premium`)
- Audit logging built-in
- Certificate rotation without script re-deployment
- Already on project roadmap

**Implementation Approach:**
- Use `Az.KeyVault` module (standard Azure PowerShell)
- Support both certificate retrieval and creation in Key Vault
- Certificate retrieved at runtime, private key operations done via Key Vault API
- Fall back to local certificate store if Key Vault unavailable

**Alternatives Considered:**
- CNG Key Storage Provider: More complex, Windows-specific, less portable
- Managed Identity only: Wouldn't work for on-premises scenarios

### Decision 3: Certificate Health Check Function

**What:** Add `Test-AuditWindowsCertificateHealth` function to check expiration.

**Why:**
- Addresses Security Audit recommendation 3.3
- Prevents silent authentication failures
- Can be integrated into scheduled task monitoring

**Design:**
- Check certificate expiration against configurable warning threshold (default: 30 days)
- Return structured object with health status
- Support both local and Key Vault certificates

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Non-exportable certs cannot be backed up | Document trade-off; recommend Key Vault for recovery needs |
| Key Vault adds Azure dependency | Make optional; local store remains default |
| Key Vault authentication complexity | Use existing Azure context; support Managed Identity |
| Breaking change if non-exportable becomes default | Keep exportable as default; recommend non-exportable in docs |

## Migration Plan

1. **Phase 1 (This Change):** Add optional hardening features
   - Existing deployments unchanged
   - New deployments can opt-in to hardening
   - Documentation updated with recommendations

2. **Phase 2 (Future):** Consider changing defaults
   - After sufficient adoption
   - With clear migration guidance

## Open Questions

1. Should Key Vault certificate creation support HSM-backed certificates automatically, or require explicit `--sku premium` setup?
   - **Proposed:** Document that users must create Key Vault with appropriate SKU; don't abstract this decision

2. Should certificate health check run automatically at script start?
   - **Proposed:** Yes, with warning output; add `-SkipCertificateHealthCheck` to suppress
