import type_checker.constant_constraints;
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

public bool checked_context_environment_constant(uint environment, uint slot,
    out uint kind, out uint payload)
{
    uint identity_mode;
    return checked_context_environment_constant_binding(environment, slot, kind, payload, identity_mode) &&
        kind >= 1u && kind <= 3u && payload != 0xffffffffu && identity_mode <= 1u;
}

public bool publish_context_constants<Graph : IParameterScopedTypeGraph>(
    uint call, InferredConstant constants[32], uint mask, uint tokens)
{
    uint2 published[32]; uint modes[32];
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            uint2 prior = (call_context_constant_mask[call] & (1u << slot)) != 0u
                ? uint2(call_context_constant_kind[call * 32u + slot], call_context_constant_payload[call * 32u + slot])
                : uint2(0u, 0xffffffffu);
            InferredConstant request = constants[slot];
            if (prior.x != 0u)
            {
                uint prior_mode = call_context_constant_identity_mode[call * 32u + slot];
                if (prior_mode > 1u) return false;
                if (prior_mode != request.identity_mode)
                {
                    InferredConstant retained = inferred_constant_reference(prior);
                    retained.identity_mode = prior_mode;
                    if (!merge_inferred_constant_claim<Graph>(retained, request, tokens)) return false;
                    request = retained;
                }
            }
            // Same-mode publications replace a producer's provisional snapshot.
            // Mixed count/exact evidence retains the compatible exact request.
            if (!publish_inferred_constant<Graph>(request, tokens, prior, published[slot])) return false;
            modes[slot] = request.identity_mode;
        }
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            call_context_constant_kind[call * 32u + slot] = published[slot].x;
            call_context_constant_payload[call * 32u + slot] = published[slot].y;
            call_context_constant_identity_mode[call * 32u + slot] = modes[slot];
        }
    call_context_constant_mask[call] |= mask;
    return true;
}
