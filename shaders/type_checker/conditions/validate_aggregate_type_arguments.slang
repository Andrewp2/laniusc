// Validate named aggregate type-argument equality requests emitted from dense
// compact HIR.
//
// The compact producer writes one request per HIR row and a counted scan turns
// each request's argument count into a compact comparison span. This pass runs
// one lane per argument pair and maps the row back to its request with a
// logarithmic prefix search.

import hir_records;
import status;
import type_checker.checked_type_graph;
import type_checker.checked_type_identity;
import type_checker.checked_slots;
import type_checker.calls.claim_lookup;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> aggregate_compare_scan_input;
StructuredBuffer<uint> aggregate_compare_prefix;
StructuredBuffer<uint> aggregate_compare_count_out;
StructuredBuffer<uint> aggregate_compare_expected_instance;
StructuredBuffer<uint> aggregate_compare_actual_instance;
StructuredBuffer<uint> aggregate_compare_error_token;
StructuredBuffer<uint> aggregate_compare_error_detail;
RWStructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_compare_count()
{
    return aggregate_compare_count_out[0u];
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint saturating_add(uint lhs, uint rhs)
{
    return lhs > 0xffffffffu - rhs ? 0xffffffffu : lhs + rhs;
}

uint request_node_for_compare(uint row)
{
    uint count = active_hir_node_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u && lo < hi; step += 1u)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint prefix = aggregate_compare_prefix[mid];
        uint width = aggregate_compare_scan_input[mid];
        uint end = saturating_add(prefix, width);
        if (end <= row)
            lo = mid + 1u;
        else
            hi = mid;
    }

    if (lo >= count)
        return INVALID;

    uint prefix = aggregate_compare_prefix[lo];
    uint width = aggregate_compare_scan_input[lo];
    return row >= prefix && row < saturating_add(prefix, width) ? lo : INVALID;
}

uint statement_call_callee_token(uint request)
{
    if (request >= active_hir_node_count()) return INVALID;
    HirCore core = compact_hir_core[request];
    HirPayload stmt = compact_hir_payload[request];
    if (core.kind != HIR_STMT && core.kind != HIR_LET_STMT &&
        core.kind != HIR_RETURN_STMT && core.kind != HIR_ASSIGN_EXPR)
        return INVALID;

    uint expression = INVALID;
    if (stmt.a == HIR_STMT_LET || stmt.a == HIR_STMT_CONST ||
        stmt.a == HIR_STMT_ASSIGN)
        expression = stmt.c;
    else if (stmt.a == HIR_STMT_RETURN)
        expression = stmt.b;
    if (expression >= active_hir_node_count() ||
        compact_hir_core[expression].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee = compact_hir_payload[expression].a;
    if (callee >= active_hir_node_count()) return INVALID;
    HirCore callee_core = compact_hir_core[callee];
    HirPayload callee_payload = compact_hir_payload[callee];
    uint token = callee_core.kind == HIR_MEMBER_EXPR
        ? callee_payload.c
        : callee_payload.d;
    return valid_token(token) ? token : callee_core.token_start;
}

bool substituted_generic_matches(
    uint request,
    uint expected_tag,
    uint expected_payload,
    uint actual_tag,
    uint actual_payload)
{
    if (actual_tag != TYPE_REF_GENERIC_PARAM)
        return false;
    uint slot = valid_token(actual_payload)
        ? type_generic_param_slot_by_token[actual_payload]
        : INVALID;
    uint callee = statement_call_callee_token(request);
    if (slot == INVALID || !valid_token(callee)) return false;

    // An argument claim owns the complete per-call type, including arrays,
    // slices, and nominal arguments. The scalar cache cannot represent it.
    uint claim_count = call_generic_claim_count_out[0u];
    uint accepted = INVALID;
    if (claim_count != 0u)
    {
        uint link = call_generic_claim_lookup_head[
            call_claim_lookup_bucket(callee, slot, claim_count)];
        for (uint step = 0u; step < claim_count && link != 0u; step++)
        {
            uint claim = link - 1u;
            if (claim >= claim_count) break;
            if (call_generic_claim_callee[claim] == callee &&
                call_generic_claim_slot[claim] == slot &&
                call_generic_claim_ref_tag[claim] != TYPE_REF_INVALID)
                accepted = min(accepted, claim);
            link = call_generic_claim_lookup_next[claim];
        }
    }
    if (accepted != INVALID)
        return checked_types_equal(CheckedSlots(), expected_tag, expected_payload,
            call_generic_claim_ref_tag[accepted], call_generic_claim_ref_payload[accepted], true);

    // Keep the existing annotation-only scalar inference when no argument
    // supplies the result parameter. Structural inference needs a claim.
    if (expected_tag != TYPE_REF_SCALAR || slot >= PARAM_CACHE_STRIDE) return false;
    uint state = callee * PARAM_CACHE_STRIDE + slot;
    uint inferred = call_generic_slot_type[state];
    if (inferred == INVALID)
    {
        uint observed;
        InterlockedCompareExchange(
            call_generic_slot_type[state], INVALID, expected_payload, observed);
        inferred = observed == INVALID ? expected_payload : observed;
    }
    return inferred == expected_payload;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

void validate_compare_row(uint row)
{
    if (row >= active_compare_count())
        return;

    uint request_node = request_node_for_compare(row);
    if (request_node == INVALID)
        return;

    uint prefix = aggregate_compare_prefix[request_node];
    uint ordinal = row - prefix;
    uint expected_instance = aggregate_compare_expected_instance[request_node];
    uint actual_instance = aggregate_compare_actual_instance[request_node];

    uint expected_tag;
    uint expected_payload;
    uint actual_tag;
    uint actual_payload;
    bool have_refs =
        ScopedCheckedTypeGraph.argument(expected_instance, ordinal, expected_tag, expected_payload) &&
        ScopedCheckedTypeGraph.argument(actual_instance, ordinal, actual_tag, actual_payload);
    // Normalization and body replay produce types without source HIR subtrees.
    // Their canonical IDs carry lexical identities and constant lengths, as
    // for ordinary applications.
    bool matches = have_refs &&
        checked_types_equal(CheckedSlots(), expected_tag, expected_payload, actual_tag, actual_payload, true);
    if (have_refs && !matches)
        matches = substituted_generic_matches(
            request_node, expected_tag, expected_payload, actual_tag, actual_payload);
    if (!matches)
    {
        record_error(
            aggregate_compare_error_token[request_node],
            ERR_ASSIGN_MISMATCH,
            aggregate_compare_error_detail[request_node]);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_compare_row(linear_thread_id(dtid));
}
