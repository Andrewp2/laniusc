import type_checker.scoped_type_equality;
import type_checker.constant_publication;
// Accepted result constraints, owned by one call HIR row. Token aliases only
// select that owner; ordered parameter references remain in caller scope.
public RWStructuredBuffer<uint> call_context_owner_by_token;
public RWStructuredBuffer<uint> call_context_arg_mask;
public RWStructuredBuffer<uint> call_context_ref_tag;
public RWStructuredBuffer<uint> call_context_ref_payload;
// Constants have independent declaration slots and tagged references. The
// mask owns validity; unpublished payload cells are never read.
public RWStructuredBuffer<uint> call_context_constant_mask;
public RWStructuredBuffer<uint> call_context_constant_kind;
public RWStructuredBuffer<uint> call_context_constant_payload;
public RWStructuredBuffer<uint> call_context_constant_identity_mode;
// Bit per slot: the published reference passed the checked constant descriptor
// in its identity mode. Every write of a present slot rewrites its bit.
public RWStructuredBuffer<uint> call_context_constant_valid_mask;

public bool checked_context_environment_argument(uint environment, uint slot,
    out uint tag, out uint payload)
{
    static const uint INVALID = 0xffffffffu;
    tag = 0u; payload = INVALID;
    if (environment == INVALID || (environment & 0x80000000u) == 0u || slot >= 32u) return false;
    uint token = environment & 0x7fffffffu;
    uint capacity; uint stride;
    call_context_owner_by_token.GetDimensions(capacity, stride);
    if (token >= capacity) return false;
    uint call = call_context_owner_by_token[token];
    call_context_arg_mask.GetDimensions(capacity, stride);
    if (call >= capacity || (call_context_arg_mask[call] & (1u << slot)) == 0u) return false;
    uint row = call * 32u + slot;
    call_context_ref_tag.GetDimensions(capacity, stride);
    if (row >= capacity) return false;
    tag = call_context_ref_tag[row]; payload = call_context_ref_payload[row];
    return tag != 0u && payload != INVALID;
}

public bool checked_context_environment_constant_binding(uint environment, uint slot,
    out uint kind, out uint payload, out uint identity_mode)
{
    static const uint INVALID = 0xffffffffu;
    kind = 0u; payload = INVALID; identity_mode = 0u;
    if (environment == INVALID || (environment & 0x80000000u) == 0u || slot >= 32u) return false;
    uint token = environment & 0x7fffffffu;
    uint capacity; uint stride;
    call_context_owner_by_token.GetDimensions(capacity, stride);
    if (token >= capacity) return false;
    uint call = call_context_owner_by_token[token];
    call_context_constant_mask.GetDimensions(capacity, stride);
    if (call >= capacity || (call_context_constant_mask[call] & (1u << slot)) == 0u) return false;
    uint row = call * 32u + slot;
    call_context_constant_kind.GetDimensions(capacity, stride);
    if (row >= capacity) return false;
    kind = call_context_constant_kind[row]; payload = call_context_constant_payload[row];
    identity_mode = call_context_constant_identity_mode[row];
    // The mask establishes presence, not validity. Binding selectors must see
    // malformed published evidence and reject it, rather than treat it absent.
    return true;
}

// Presence as above, plus the descriptor admission recorded at publication.
public bool checked_context_environment_constant_evidence(uint environment, uint slot,
    out uint kind, out uint payload, out uint identity_mode, out bool valid)
{
    valid = false;
    if (!checked_context_environment_constant_binding(environment, slot, kind, payload, identity_mode))
        return false;
    uint call = call_context_owner_by_token[environment & 0x7fffffffu];
    uint capacity; uint stride;
    call_context_constant_valid_mask.GetDimensions(capacity, stride);
    valid = call < capacity && (call_context_constant_valid_mask[call] & (1u << slot)) != 0u;
    return true;
}

public bool checked_context_environment_constant(uint environment, uint slot,
    out uint kind, out uint payload)
{
    uint identity_mode;
    return checked_context_environment_constant_binding(environment, slot, kind, payload, identity_mode) &&
        kind >= 1u && kind <= 3u && payload != 0xffffffffu && identity_mode <= 1u;
}
