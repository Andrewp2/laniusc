// Validate declared call generic parameters from compact requirement rows.
//
// This pass walks compact `(call, slot)` requirement rows and probes the exact
// claim index to verify each declared generic slot was either concretely
// inferred or at least touched by an unknown-typed argument. Missing slots get a
// diagnostic at the call site.

import hir_records;
import status;
import type_checker.calls.claim_lookup;
import type_checker.calls.claim_reference;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.calls.checked_constant_environment;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
StructuredBuffer<uint> call_required_generic_count_out;
StructuredBuffer<uint> call_required_generic_scan_input;
StructuredBuffer<uint> call_required_generic_prefix;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;
// The status words before the final validation passes.
StructuredBuffer<uint> status_prior;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_MISSING_CONSTANT_BINDING = 23u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[ForceInline]
uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u
        ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_required_generic_count()
{
    return call_required_generic_count_out[0u];
}

uint generic_claim_capacity()
{
    uint base = max(active_token_count(), active_hir_node_count());
    uint max_base = 0xffffffffu / GENERIC_CLAIM_CAPACITY_MULTIPLIER;
    return base > max_base ? 0xffffffffu : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
}

uint active_generic_claim_count()
{
    return min(call_generic_claim_count_out[0u], generic_claim_capacity());
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

#include "callable_generic_requirements.slang"

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = compact_hir_payload[call_node].a;
    // A member's leaf owns this call; its span can begin in a receiver call.
    if (valid_node(callee_node) && compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_node].c;
        return valid_token(member_token) ? member_token : INVALID;
    }
    uint call_token = compact_hir_core[call_node].token_start;
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint callee_token = payload.d;
    if (!valid_token(callee_token))
        callee_token = callee.token_start;
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_node_for_requirement(uint requirement_i)
{
    uint node_count = active_hir_node_count();
    uint lo = 0u;
    uint hi = node_count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = call_required_generic_prefix[mid];
        uint count = call_required_generic_scan_input[mid];
        uint end = start + count;
        if (requirement_i < start)
            hi = mid;
        else if (requirement_i >= end)
            lo = mid + 1u;
        else
            return mid;
    }
    return INVALID;
}

uint concrete_claim_key(uint row)
{
    return call_generic_claim_callee[row] != INVALID &&
           call_generic_claim_slot[row] != INVALID &&
           checked_claim_reference(call_generic_claim_ref_tag[row], call_generic_claim_ref_payload[row])
        ? 1u
        : 0u;
}

uint find_generic_claim(uint callee_token, uint slot, bool require_concrete)
{
    uint count = active_generic_claim_count();
    uint bucket = call_claim_lookup_bucket(callee_token, slot, count);
    uint link = call_generic_claim_lookup_head[bucket];
    uint result = INVALID;
    for (uint step = 0u; step < count && link != 0u; step += 1u)
    {
        uint row = link - 1u;
        if (row >= count)
            break;
        if (call_generic_claim_callee[row] == callee_token &&
            call_generic_claim_slot[row] == slot &&
            (!require_concrete || concrete_claim_key(row) != 0u))
        {
            result = min(result, row);
        }
        link = call_generic_claim_lookup_next[row];
    }
    return result;
}

bool has_concrete_generic_claim(uint callee_token, uint slot)
{
    return find_generic_claim(callee_token, slot, true) != INVALID;
}

bool has_any_generic_claim(uint callee_token, uint slot)
{
    return find_generic_claim(callee_token, slot, false) != INVALID;
}

static const uint REQUIRED_SLOT_MISSING = 0u;
static const uint REQUIRED_SLOT_TOUCHED_UNKNOWN = 1u;
static const uint REQUIRED_SLOT_INFERRED = 2u;

uint required_slot_status(uint callee_i, uint slot)
{
    if (has_concrete_generic_claim(callee_i, slot))
        return REQUIRED_SLOT_INFERRED;

    uint tag; uint payload;
    if (checked_explicit_environment_argument(0x80000000u | callee_i, slot, tag, payload) ||
        checked_context_environment_argument(0x80000000u | callee_i, slot, tag, payload))
        return REQUIRED_SLOT_INFERRED;

    return has_any_generic_claim(callee_i, slot)
        ? REQUIRED_SLOT_TOUCHED_UNKNOWN
        : REQUIRED_SLOT_MISSING;
}

void validate_required_generic(uint requirement_i)
{
    if (requirement_i >= active_required_generic_count())
        return;

    uint call_node = call_node_for_requirement(requirement_i);
    if (!valid_node(call_node) ||
        compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;

    uint start = call_required_generic_prefix[call_node];
    uint count = call_required_generic_scan_input[call_node];
    if (requirement_i < start || requirement_i >= start + count)
        return;

    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) ||
        call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;
    // An error already recorded inside the call (an argument that does not
    // match its parameter, such as a length that does not fit) is why a
    // binding is missing; it is the diagnostic.
    HirCore call_core = compact_hir_core[call_node];
    bool explained = language_error_recorded_within(status_prior, call_core.token_start, call_core.token_end);

    uint2 counts = required_callable_generic_counts(callee_i);
    uint slot = requirement_i - start;
    uint generic_count = counts.x;
    if (slot >= generic_count)
    {
        uint constant_slot = slot - generic_count;
        if (constant_slot >= counts.y) return;
        uint kind; uint value;
        if (!checked_call_environment_constant_ref(0x80000000u | callee_i,
                constant_slot, kind, value))
        {
            call_return_type[callee_i] = TY_UNKNOWN;
            if (!explained && !explicit_application_operand_diagnosed(callee_i))
                record_error(callee_i, ERR_MISSING_CONSTANT_BINDING, constant_slot);
        }
        return;
    }

    uint slot_status = required_slot_status(callee_i, slot);
    if (slot_status == REQUIRED_SLOT_INFERRED)
        return;

    call_return_type[callee_i] = TY_UNKNOWN;
    if (slot_status == REQUIRED_SLOT_TOUCHED_UNKNOWN || explained ||
        explicit_application_operand_diagnosed(callee_i))
        return;

    record_error(
        callee_i,
        ERR_ASSIGN_MISMATCH,
        (TY_GENERIC_BASE + slot) * 256u + TY_UNKNOWN);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_required_generic(linear_thread_id(dtid));
}
