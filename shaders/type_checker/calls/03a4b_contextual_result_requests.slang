// Match a direct call's declared aggregate result against the aggregate type
// required by its enclosing declaration or return statement. One lane emits
// one variable-width comparison request; the existing prefix scan expands the
// type arguments so contextual generic inference remains parallel.

import external_type_identity;
import hir_records;
import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;

RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_CONST = 4u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint callee_token(uint call)
{
    uint call_token = compact_hir_core[call].token_start;
    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee)) return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token)) token = core.token_start;
    return valid_token(token) ? token : INVALID;
}

bool same_named_identity(uint expected, uint actual)
{
    uint expected_decl = type_instance_decl_token[expected];
    uint actual_decl = type_instance_decl_token[actual];
    if (valid_token(expected_decl) || valid_token(actual_decl))
        return valid_token(expected_decl) && expected_decl == actual_decl;
    return external_type_identity_equal(expected, actual);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload stmt = compact_hir_payload[node];
    if (core.kind != HIR_STMT && core.kind != HIR_LET_STMT &&
        core.kind != HIR_RETURN_STMT)
        return;

    uint call = INVALID;
    uint expected_tag = 0u;
    uint expected = INVALID;
    if (stmt.a == HIR_STMT_LET || stmt.a == HIR_STMT_CONST)
    {
        call = stmt.c;
        if (valid_hir(stmt.d))
        {
            uint type_token = compact_hir_core[stmt.d].token_start;
            if (valid_token(type_token))
            {
                expected_tag = type_expr_ref_tag[type_token];
                expected = type_expr_ref_payload[type_token];
            }
        }
    }
    else if (stmt.a == HIR_STMT_RETURN)
    {
        call = stmt.b;
        uint fn_node = compact_hir_nearest_fn[node];
        if (valid_hir(fn_node))
        {
            uint fn = compact_hir_payload[fn_node].b;
            if (valid_token(fn))
            {
                expected_tag = fn_return_ref_tag[fn];
                expected = fn_return_ref_payload[fn];
            }
        }
    }
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR ||
        expected_tag != TYPE_REF_INSTANCE || !valid_token(expected))
        return;

    uint callee = callee_token(call);
    uint fn = valid_token(callee) ? call_fn_index[callee] : INVALID;
    if (!valid_token(fn) || fn_return_ref_tag[fn] != TYPE_REF_INSTANCE)
        return;
    uint actual = fn_return_ref_payload[fn];
    uint expected_kind = type_instance_kind[expected];
    uint actual_kind = valid_token(actual) ? type_instance_kind[actual] : 0u;
    bool matches = valid_token(actual) &&
        expected_kind == actual_kind &&
        type_instance_arg_count[expected] == type_instance_arg_count[actual] &&
        (expected_kind != TYPE_INSTANCE_NAMED ||
         same_named_identity(expected, actual));
    if (!matches)
    {
        record_min_token_error(status, compact_hir_core[call].token_start,
                               ERR_ASSIGN_MISMATCH, 0u);
        return;
    }
    uint count = type_instance_arg_count[expected];
    if (count == 0u) return;
    aggregate_compare_scan_input[node] = count;
    aggregate_compare_expected_instance[node] = expected;
    aggregate_compare_actual_instance[node] = actual;
    aggregate_compare_error_token[node] = compact_hir_core[call].token_start;
    aggregate_compare_error_detail[node] = 0u;
}
