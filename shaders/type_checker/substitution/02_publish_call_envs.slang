// Publish each call's environments as CT_ENV records (call_env.slang). One
// lane per call node. Bindings keep the old graphs' selection order:
//
// - value (03e): explicit, argument claims in claim order, result context;
// - expected (03k): explicit, result context, then argument claims ranked by
//   literal context (a literal that can take context ranks after a value of
//   known type);
// - constants (both): checked_call_environment_constant_ref.
//
// A binding is interned on demand (ct_checked.slang) and the environment is
// built by ct_env.slang, which re-interns it only when its bindings differ
// from the published one, so a stable call reserves nothing in later rounds.
import hir_records;
import primitive_types;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;
import type_checker.substitution.ct_checked;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.call_env;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_env;
import type_checker.calls.checked_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.claim_lookup;
import type_checker.calls.claim_reference;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_generic_claim_arg_row;
StructuredBuffer<uint> call_arg_row_literal_context_mask;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> type_decl_generic_param_count;

static const uint INVALID = 0xffffffffu;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_node(uint node) { return node < hir_count(); }
bool valid_token(uint token) { return token < gParams.n_tokens; }

#include "../calls/callable_generic_requirements.slang"

// The low `count` bits.
uint low_bits(uint count) { return count == 0u ? 0u : 0xffffffffu >> (32u - min(count, 32u)); }

// The type and constant slots the call's result context binds
// (contextual_call_environment.slang).
uint2 context_masks(uint token)
{
    uint capacity; uint stride;
    call_context_owner_by_token.GetDimensions(capacity, stride);
    if (token >= capacity) return uint2(0u, 0u);
    uint call = call_context_owner_by_token[token];
    call_context_arg_mask.GetDimensions(capacity, stride);
    uint types = call < capacity ? call_context_arg_mask[call] : 0u;
    call_context_constant_mask.GetDimensions(capacity, stride);
    uint constants = call < capacity ? call_context_constant_mask[call] : 0u;
    return uint2(types, constants);
}

// The candidate type and constant slots of a call: its callee's composed
// arity (a method's own parameters and its impl's) once the callee is
// resolved, else every slot. A non-generic call then publishes the empty
// environment without visiting a slot. A trait's required member reached
// through a bound (methods/07a, dependencies/15b) also has the trait's
// slots, which its header does not declare: the bound's trait arguments
// are its context.
uint2 candidate_masks(uint token)
{
    if (call_dependency_library_id[token] == INVALID && !valid_token(call_fn_index[token]))
        return uint2(0xffffffffu, 0xffffffffu);
    uint2 counts = required_callable_generic_counts(token);
    return uint2(low_bits(counts.x), low_bits(counts.y)) | context_masks(token);
}

// Numeric literals can receive context within their category; named values,
// Boolean literals and structural values keep their known types.
uint literal_claim_rank(uint row)
{
    uint scalar = call_generic_claim_ref_payload[row];
    if (call_generic_claim_ref_tag[row] != 1u || (!scalar_is_integer(scalar) && !scalar_is_float(scalar))) return 0u;
    uint argument = call_generic_claim_arg_row[row];
    if (argument >= min(call_arg_row_count_out[0u], gParams.n_hir_nodes)) return 0u;
    return (call_arg_row_literal_context_mask[argument] & (scalar_is_float(scalar) ? 2u : 1u)) != 0u ? 1u : 0u;
}

// The accepted claim of (callee, slot): the first row, or with `ranked` the
// first row of the lowest literal rank.
bool claim_binding(uint callee, uint slot, bool ranked, out uint tag, out uint payload)
{
    tag = 0u; payload = INVALID;
    uint capacity; uint stride;
    call_generic_claim_callee.GetDimensions(capacity, stride);
    uint count = min(call_generic_claim_count_out[0u], capacity);
    if (count == 0u) return false;
    uint link = call_generic_claim_lookup_head[call_claim_lookup_bucket(callee, slot, count)];
    uint accepted = INVALID;
    uint accepted_rank = INVALID;
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) return false;
        if (call_generic_claim_callee[row] == callee && call_generic_claim_slot[row] == slot &&
            checked_claim_reference(call_generic_claim_ref_tag[row], call_generic_claim_ref_payload[row]))
        {
            uint rank = ranked ? literal_claim_rank(row) : 0u;
            if (rank < accepted_rank || (rank == accepted_rank && row < accepted))
            { accepted = row; accepted_rank = rank; }
        }
        link = call_generic_claim_lookup_next[row];
    }
    if (accepted == INVALID) return false;
    tag = call_generic_claim_ref_tag[accepted]; payload = call_generic_claim_ref_payload[accepted];
    return true;
}

// The checked operand bound to `item` (type slots 0..31, then constant
// slots) in environment `which` (0 value, 1 expected).
bool binding_operand(uint token, uint which, uint item, out uint tag, out uint payload)
{
    uint environment = 0x80000000u | token;
    tag = 0u; payload = INVALID;
    if (item >= CT_ENV_SLOTS)
    {
        uint kind; uint value;
        if (!checked_call_environment_constant_ref(environment, item - CT_ENV_SLOTS, kind, value) ||
            kind < 1u || kind > 3u || value == INVALID) return false;
        tag = CT_CONSTANT_TAG_BIT | kind; payload = value;
        return true;
    }
    if (checked_explicit_environment_argument(environment, item, tag, payload)) return true;
    uint context_tag; uint context_payload;
    bool context = checked_context_environment_argument(environment, item, context_tag, context_payload);
    if (!context || which == 0u)
    {
        if (claim_binding(token, item, which == 1u, tag, payload)) return true;
    }
    tag = context_tag; payload = context_payload;
    return context;
}

// The callee token of a call node, or INVALID.
uint call_token(uint call)
{
    uint kind = compact_hir_core[call].kind;
    if (kind == 28u || kind == 33u) return compact_hir_core[call].token_start;
    if (kind != 19u) return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return INVALID;
    bool dotted = compact_hir_core[callee].kind == 21u;
    uint token = dotted ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    return token < gParams.n_tokens ? token : compact_hir_core[callee].token_start;
}

// The bindings of one call environment, interned on demand.
struct CallEnvBindings : ICtEnvBindings
{
    uint token;
    uint which;
    uint spare;
    [mutating] uint binding(uint item)
    {
        uint tag; uint payload;
        return binding_operand(token, which, item, tag, payload)
            ? ct_intern_checked<CtCheckedRows>(tag, payload, spare) : CT_NONE;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    if (call >= hir_count()) return;
    uint token = call_token(call);
    if (token >= gParams.n_tokens) return;
    uint2 published = ct_call_env(token);
    CtSpare spare = ct_spare_none();
    CallEnvBindings bindings;
    bindings.token = token;
    bindings.spare = CT_NONE;
    uint2 masks = candidate_masks(token);
    for (uint which = 0u; which < 2u; which++)
    {
        bindings.which = which;
        uint prior = which == 0u ? published.x : published.y;
        // An unbound candidate slot is a hole.
        uint environment = ct_env_publish(bindings, masks.x, masks.y,
            CT_ENV_PARTIAL, prior, spare);
        if (!ct_is_resolved(environment) || environment == prior) continue;
        if (which == 0u) call_env_ct[token].x = environment;
        else call_env_ct[token].y = environment;
    }
}
