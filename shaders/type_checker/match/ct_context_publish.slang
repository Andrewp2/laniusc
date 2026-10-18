// Publish a matched environment (a CT_ENV from ct_match) as a call's context
// bindings, in the tables argument and result inference read
// (contextual_call_environment.slang): call_context_ref_* for type slots,
// call_context_constant_* for constant slots. A binding is written as an
// existing operand of its ID when the call already holds one, else as the
// checked row of its ID (ct_realize). There is no per-lane array: pass 0
// checks every binding and realizes its row, pass 1 writes them.
//
// The publisher interns nothing. A prior operand without an ID yet ends the
// call with CT_PUBLISH_INTERN and the operand; the caller interns it at its
// own single ct_intern_checked site and calls again with the result, so a
// kernel keeps one inlined interner for its own operands and the priors.
//
// Constants merge with the context table's claim of the slot as constant
// publication always has: a claim of the same identity mode is replaced, a
// claim of the other mode must be compatible ("Constant claims" in
// docs/canonical-type-ids.md) and the exact one is kept.
//
// Callers own the call's owner tokens (call_context_owner_by_token).
import type_checker.mutable_checked_type_graph;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;

// Flags.
// Type bindings must agree with the call's explicit and contextual types.
public static const uint CT_PUBLISH_TYPE_PRIORS = 1u;
// Constant bindings first merge with the call environment's binding.
public static const uint CT_PUBLISH_ENV_CONSTANTS = 2u;
// Record the published constants as admitted (their valid bits); without it
// a later admission pass owns the bits.
public static const uint CT_PUBLISH_ADMIT = 4u;
// The call's argument claims (ICtClaims) and constant bindings bind the
// pattern already: a claimed type slot must agree with its claim, every
// constant slot must agree with the call's binding, and only unclaimed type
// slots are published.
public static const uint CT_PUBLISH_CLAIMS = 8u;

// The kernel's argument claim of (callee token, type slot).
public interface ICtClaims
{
    static bool claim(uint token, uint slot, out uint tag, out uint payload);
}

public struct CtNoClaims : ICtClaims
{
    public static bool claim(uint token, uint slot, out uint tag, out uint payload)
    {
        tag = 0u;
        payload = 0xffffffffu;
        return false;
    }
}

// Outcomes.
public static const uint CT_PUBLISHED = 0u;
public static const uint CT_PUBLISH_REJECTED = 1u;
// A row this lane needs is being written by another lane: retry next round.
public static const uint CT_PUBLISH_BUSY = 2u;
// Out of rows: the capacity error constant publication reports
// (ERR 6, 0x474e0001).
public static const uint CT_PUBLISH_CAPACITY = 3u;
// A prior operand (`request`) has no ID yet: intern it and call again with
// (operand, ID) as `interned`. An operand that does not intern never agrees
// with a binding, so the caller can reject the publication instead.
public static const uint CT_PUBLISH_INTERN = 4u;
// The most requests one publication makes (each item and source once).
public static const uint CT_PUBLISH_REQUEST_LIMIT = 128u;

static const uint INVALID = 0xffffffffu;

// The scalar of a typed constant ID, or 0.
uint constant_scalar(uint ref)
{
    SourceSlots slots;
    if (ct_is_const_param(ref)) return ct_param_scalar<SourceSlots>(slots, ref);
    if (!ct_is_record(ref)) return 0u;
    uint kind = ct_kind(ref);
    return kind == CC_KIND_VALUE || kind == CC_KIND_CAST ? ct_words(ref).x : 0u;
}

// One result scalar, and typed identity when both claims are exact, count
// identity otherwise.
bool constant_claims_compatible(uint left, uint left_mode, uint right, uint right_mode)
{
    if (constant_scalar(left) != constant_scalar(right)) return false;
    if (left_mode == 0u && right_mode == 0u) return left == right;
    return cc_count_class(left) == cc_count_class(right);
}

// The prior evidence of item `item` (type slot, or 32 + constant slot) from
// `source`: types 0 explicit (the claim with CT_PUBLISH_CLAIMS), 1 context;
// constants 0 the call environment's binding, 1 the context table. Operands
// carry the constant tag.
bool prior_operand<C : ICtClaims>(uint call, uint token, uint item, uint source, uint flags,
    out uint2 operand, out uint mode)
{
    uint environment = 0x80000000u | token;
    uint slot = item & 31u;
    operand = uint2(0u, INVALID);
    mode = 0u;
    if (item < 32u)
    {
        if (source == 1u) return checked_context_environment_argument(environment, slot, operand.x, operand.y);
        if ((flags & CT_PUBLISH_CLAIMS) != 0u)
            return C.claim(token, slot, operand.x, operand.y) && operand.x != 0u && operand.y != INVALID;
        return checked_explicit_environment_argument(environment, slot, operand.x, operand.y);
    }
    uint kind; uint value;
    if (source == 0u)
    {
        uint selected;
        if (!checked_call_environment_constant_binding(environment, slot, kind, value, mode, selected))
            return false;
    }
    else
    {
        if ((call_context_constant_mask[call] & (1u << slot)) == 0u) return false;
        kind = call_context_constant_kind[call * 32u + slot];
        value = call_context_constant_payload[call * 32u + slot];
        mode = call_context_constant_identity_mode[call * 32u + slot];
    }
    operand = uint2(CT_CONSTANT_TAG_BIT | kind, value);
    return kind != 0u && value != INVALID;
}

// The checked operand of `id`, realizing its row when it has none.
uint realize_operand(uint id, out uint2 operand)
{
    uint failure;
    operand = ct_realize(id, failure);
    if (failure == CT_REALIZE_BUSY) return CT_PUBLISH_BUSY;
    if (failure == CT_REALIZE_CAPACITY) return CT_PUBLISH_CAPACITY;
    if (failure != 0u || operand.x == 0u) return CT_PUBLISH_REJECTED;
    operand.x &= ~CT_ROW_CONSTANT_TAG;
    return CT_PUBLISHED;
}

// The ID of a prior operand, CT_PENDING when it must be interned first.
// `interned` is the caller's last interned request: (tag, payload, ID).
uint prior_id(uint2 operand, uint3 interned)
{
    uint id = ct_ref(operand.x, operand.y);
    if (id != CT_PENDING && id != CT_NONE) return id;
    return all(operand == interned.xy) ? interned.z : CT_PENDING;
}

// Publish the bindings of `env` in the slot masks `types` and `constants` as
// call `call`'s context; `token` names the call environment. `count_mask` is
// the constant slots bound by count claims only (ct_match's). C supplies
// argument claims. CT_PUBLISH_INTERN asks for `request` to be interned (see
// above); nothing is written until the call publishes.
public uint ct_publish_context<C : ICtClaims>(uint call, uint token, uint env,
    uint types, uint constants, uint count_mask, uint flags, uint3 interned, out uint2 request)
{
    bool changed;
    return ct_publish_context_tracked<C, false>(call, token, env, types, constants, count_mask, flags,
        interned, request, changed);
}

// ct_publish_context that also reports whether the publication changed the
// call's context: a slot it writes was unbound or held another operand, or a
// constant it admits was not admitted yet.
public uint ct_publish_context_changes<C : ICtClaims>(uint call, uint token, uint env,
    uint types, uint constants, uint count_mask, uint flags, uint3 interned, out uint2 request,
    out bool changed)
{
    return ct_publish_context_tracked<C, true>(call, token, env, types, constants, count_mask, flags,
        interned, request, changed);
}

// The publisher; only TRACK computes `changed` (false otherwise).
uint ct_publish_context_tracked<C : ICtClaims, let TRACK : bool>(uint call, uint token, uint env,
    uint types, uint constants, uint count_mask, uint flags, uint3 interned, out uint2 request,
    out bool changed)
{
    request = uint2(0u, INVALID);
    changed = false;
    bool claims = (flags & CT_PUBLISH_CLAIMS) != 0u;
    uint written_types = 0u;
    uint written_constants = 0u;
    for (uint pass = 0u; pass < 2u; pass++)
    {
        for (uint item = 0u; item < 64u; item++)
        {
            bool constant = item >= 32u;
            uint slot = item & 31u;
            uint bit = 1u << slot;
            if (((constant ? constants : types) & bit) == 0u) continue;
            uint retained = ct_env_binding(env, slot, constant);
            if (!ct_is_resolved(retained)) return CT_PUBLISH_REJECTED;
            uint mode = constant && (count_mask & bit) != 0u ? 1u : 0u;
            // An existing operand that spells the retained binding.
            uint2 spelled = uint2(0u, INVALID);
            // A slot the claims bind is checked, not published.
            bool bound = false;
            [loop]
            for (uint source = 0u; source < 2u; source++)
            {
                bool wanted = constant
                    ? (source == 0u ? (flags & (CT_PUBLISH_ENV_CONSTANTS | CT_PUBLISH_CLAIMS)) != 0u : !claims)
                    : (source == 0u ? (flags & (CT_PUBLISH_TYPE_PRIORS | CT_PUBLISH_CLAIMS)) != 0u
                        : (flags & CT_PUBLISH_TYPE_PRIORS) != 0u);
                if (!wanted) continue;
                uint2 prior; uint prior_mode;
                if (!prior_operand<C>(call, token, item, source, flags, prior, prior_mode)) continue;
                uint id = prior_id(prior, interned);
                uint2 operand = uint2(prior.x & ~CT_CONSTANT_TAG_BIT, prior.y);
                // The context table's claim of the same mode is replaced; it
                // only lends its spelling, which an uninterned claim need not.
                if (constant && source == 1u && prior_mode == mode)
                {
                    if (id == retained) spelled = operand;
                    continue;
                }
                if (id == CT_PENDING)
                {
                    request = prior;
                    return CT_PUBLISH_INTERN;
                }
                if (!constant)
                {
                    // Explicit and checked contextual facts (or the claims)
                    // have authority and must each agree.
                    if (id != retained) return CT_PUBLISH_REJECTED;
                    if (source == 1u) spelled = prior;
                    bound = bound || claims;
                    continue;
                }
                if (prior_mode > 1u || !ct_is_resolved(id) ||
                    !constant_claims_compatible(id, prior_mode, retained, mode))
                    return CT_PUBLISH_REJECTED;
                bound = bound || claims;
                // An exact claim wins; between claims of one mode the prior stays.
                if (mode < prior_mode) continue;
                retained = id;
                mode = prior_mode;
                spelled = operand;
            }
            // With claims, every constant slot must be bound by the call.
            if (claims && constant && !bound) return CT_PUBLISH_REJECTED;
            if (bound) continue;
            uint2 operand = spelled;
            if (operand.x == 0u)
            {
                uint outcome = realize_operand(retained, operand);
                if (outcome != CT_PUBLISHED) return outcome;
            }
            if (pass == 0u) continue;
            uint row = call * 32u + slot;
            if (!constant)
            {
                if (TRACK)
                    changed = changed || (call_context_arg_mask[call] & bit) == 0u ||
                        call_context_ref_tag[row] != operand.x || call_context_ref_payload[row] != operand.y;
                call_context_ref_tag[row] = operand.x;
                call_context_ref_payload[row] = operand.y;
                written_types |= bit;
                continue;
            }
            if (TRACK)
                changed = changed || (call_context_constant_mask[call] & bit) == 0u ||
                    call_context_constant_kind[row] != operand.x || call_context_constant_payload[row] != operand.y ||
                    call_context_constant_identity_mode[row] != mode;
            call_context_constant_kind[row] = operand.x;
            call_context_constant_payload[row] = operand.y;
            call_context_constant_identity_mode[row] = mode;
            written_constants |= bit;
        }
    }
    call_context_arg_mask[call] |= written_types;
    // Realized and retained constants are checked references.
    if ((flags & CT_PUBLISH_ADMIT) != 0u)
    {
        if (TRACK)
            changed = changed || (call_context_constant_valid_mask[call] & written_constants) != written_constants;
        call_context_constant_valid_mask[call] |= written_constants;
    }
    call_context_constant_mask[call] |= written_constants;
    return CT_PUBLISHED;
}
