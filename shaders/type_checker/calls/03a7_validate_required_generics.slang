// Validate required direct-call generic parameters from compact requirement rows.
//
// The generic claim stream is sorted by (callee, slot, concrete-claim flag).
// This pass walks compact `(call, slot)` requirement rows and binary-searches
// that stream to verify each declared generic slot was either concretely
// inferred or at least touched by an unknown-typed argument. Missing slots get a
// diagnostic at the call site.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> call_generic_slot_ordinal;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> call_generic_claim_order;
StructuredBuffer<uint> call_required_generic_count_out;
StructuredBuffer<uint> call_required_generic_scan_input;
StructuredBuffer<uint> call_required_generic_prefix;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

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

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint callee_token = callee.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(callee_token))
        callee_token = callee.token_start;
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = compact_hir_payload[call_node].a;
    return valid_node(callee_node) &&
        compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR;
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

uint nullable_key(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

uint concrete_claim_key(uint row)
{
    return call_generic_claim_callee[row] != INVALID &&
           call_generic_claim_slot[row] != INVALID &&
           call_generic_claim_type[row] != TY_UNKNOWN
        ? 1u
        : 0u;
}

bool generic_claim_key_less(uint row, uint callee_token, uint slot, uint concrete)
{
    uint row_callee = nullable_key(call_generic_claim_callee[row]);
    uint key_callee = nullable_key(callee_token);
    if (row_callee != key_callee)
        return row_callee < key_callee;

    uint row_slot = nullable_key(call_generic_claim_slot[row]);
    uint key_slot = nullable_key(slot);
    if (row_slot != key_slot)
        return row_slot < key_slot;

    return concrete_claim_key(row) < concrete;
}

uint lower_bound_generic_claim(uint callee_token, uint slot, uint concrete)
{
    uint count = active_generic_claim_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = call_generic_claim_order[mid];
        if (row >= count || !generic_claim_key_less(row, callee_token, slot, concrete))
            hi = mid;
        else
            lo = mid + 1u;
    }
    return lo < count ? call_generic_claim_order[lo] : INVALID;
}

bool generic_claim_matches(uint row, uint callee_token, uint slot)
{
    return row != INVALID &&
           row < active_generic_claim_count() &&
           call_generic_claim_callee[row] == callee_token &&
           call_generic_claim_slot[row] == slot;
}

bool has_concrete_generic_claim(uint callee_token, uint slot)
{
    uint row = lower_bound_generic_claim(callee_token, slot, 1u);
    return generic_claim_matches(row, callee_token, slot) &&
           call_generic_claim_type[row] != TY_UNKNOWN;
}

bool has_any_generic_claim(uint callee_token, uint slot)
{
    uint row = lower_bound_generic_claim(callee_token, slot, 0u);
    return generic_claim_matches(row, callee_token, slot);
}

static const uint REQUIRED_SLOT_MISSING = 0u;
static const uint REQUIRED_SLOT_TOUCHED_UNKNOWN = 1u;
static const uint REQUIRED_SLOT_INFERRED = 2u;

uint required_slot_status(uint callee_i, uint slot)
{
    if (has_concrete_generic_claim(callee_i, slot))
        return REQUIRED_SLOT_INFERRED;

    if (slot < PARAM_CACHE_STRIDE)
    {
        uint state_i = callee_i * PARAM_CACHE_STRIDE + slot;
        if (call_generic_slot_type[state_i] != INVALID)
            return REQUIRED_SLOT_INFERRED;
        if (call_generic_slot_ordinal[state_i] != INVALID)
            return REQUIRED_SLOT_TOUCHED_UNKNOWN;
    }

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
        compact_hir_core[call_node].kind != HIR_CALL_EXPR ||
        call_record_is_member_call(call_node))
        return;

    uint start = call_required_generic_prefix[call_node];
    uint count = call_required_generic_scan_input[call_node];
    if (requirement_i < start || requirement_i >= start + count)
        return;

    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) ||
        method_call_name_id[callee_i] != INVALID ||
        call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint fn_i = call_fn_index[callee_i];
    if (!valid_token(fn_i))
        return;

    uint slot = requirement_i - start;
    uint generic_count = type_decl_generic_param_count[fn_i];
    if (slot >= generic_count)
        return;

    uint slot_status = required_slot_status(callee_i, slot);
    if (slot_status == REQUIRED_SLOT_INFERRED)
        return;

    call_return_type[callee_i] = TY_UNKNOWN;
    if (slot_status == REQUIRED_SLOT_TOUCHED_UNKNOWN)
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
