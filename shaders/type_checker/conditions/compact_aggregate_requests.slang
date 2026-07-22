// Produce aggregate-structure comparison requests from dense compact HIR and
// canonical checked expression references. One lane owns one statement HIR
// row; variable-length type arguments are expanded by the downstream scan and
// aggregate_args pass, never walked serially here.

import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
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
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

void clear_request(uint node)
{
    aggregate_compare_scan_input[node] = 0u;
    aggregate_compare_expected_instance[node] = INVALID;
    aggregate_compare_actual_instance[node] = INVALID;
    aggregate_compare_error_token[node] = INVALID;
    aggregate_compare_error_detail[node] = 0u;
}

void declaration_ref(uint token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(token)) return;
    uint decl = visible_decl[token];
    if (!valid_token(decl)) decl = token;
    tag = decl_type_ref_tag[decl];
    payload = decl_type_ref_payload[decl];
}

void type_node_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_hir(node)) return;
    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token)) return;
    tag = type_expr_ref_tag[token];
    payload = type_expr_ref_payload[token];
}

void expression_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_hir(node)) return;
    tag = semantic_expr_ref_tag_by_hir[node];
    payload = semantic_expr_ref_payload_by_hir[node];
}

bool same_generic_slot(uint lhs, uint rhs, bool is_const)
{
    if (!valid_token(lhs) || !valid_token(rhs)) return false;
    uint lhs_slot = is_const
        ? type_const_param_slot_by_token[lhs]
        : type_generic_param_slot_by_token[lhs];
    uint rhs_slot = is_const
        ? type_const_param_slot_by_token[rhs]
        : type_generic_param_slot_by_token[rhs];
    return lhs_slot != INVALID && lhs_slot == rhs_slot;
}

bool same_leaf_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    if (lhs_tag != rhs_tag) return false;
    if (lhs_tag == TYPE_REF_GENERIC_PARAM)
        return same_generic_slot(lhs_payload, rhs_payload, false);
    return lhs_payload == rhs_payload;
}

bool same_length(uint lhs, uint rhs)
{
    uint lhs_kind = type_instance_len_kind[lhs];
    uint rhs_kind = type_instance_len_kind[rhs];
    if (lhs_kind != rhs_kind) return false;
    uint lhs_payload = type_instance_len_payload[lhs];
    uint rhs_payload = type_instance_len_payload[rhs];
    return lhs_kind == TYPE_LEN_CONST_PARAM
        ? same_generic_slot(lhs_payload, rhs_payload, true)
        : lhs_payload == rhs_payload;
}

bool same_named_identity(uint lhs, uint rhs)
{
    uint lhs_decl = type_instance_decl_token[lhs];
    uint rhs_decl = type_instance_decl_token[rhs];
    if (valid_token(lhs_decl) || valid_token(rhs_decl))
        return valid_token(lhs_decl) && lhs_decl == rhs_decl;
    uint lhs_external = type_instance_external_canonical[lhs];
    uint rhs_external = type_instance_external_canonical[rhs];
    return lhs_external != INVALID && lhs_external == rhs_external;
}

bool prepare_instance_compare(uint node, uint expected, uint actual, uint error_token)
{
    if (expected == actual) return true;
    if (!valid_token(expected) || !valid_token(actual)) return false;
    uint kind = type_instance_kind[expected];
    if (kind == 0u || kind != type_instance_kind[actual]) return false;
    if (kind == TYPE_INSTANCE_ARRAY || kind == TYPE_INSTANCE_SLICE)
    {
        if (!same_leaf_ref(
                type_instance_elem_ref_tag[expected],
                type_instance_elem_ref_payload[expected],
                type_instance_elem_ref_tag[actual],
                type_instance_elem_ref_payload[actual]))
            return false;
        return kind != TYPE_INSTANCE_ARRAY || same_length(expected, actual);
    }
    if (kind != TYPE_INSTANCE_NAMED || !same_named_identity(expected, actual))
        return false;
    uint count = type_instance_arg_count[expected];
    if (count != type_instance_arg_count[actual]) return false;
    if (count != 0u)
    {
        aggregate_compare_scan_input[node] = count;
        aggregate_compare_expected_instance[node] = expected;
        aggregate_compare_actual_instance[node] = actual;
        aggregate_compare_error_token[node] = error_token;
        aggregate_compare_error_detail[node] = 0u;
    }
    return true;
}

void validate_refs(uint node, uint expected_tag, uint expected_payload,
                   uint actual_tag, uint actual_payload, uint error_token)
{
    if (expected_tag == TYPE_REF_INVALID || actual_tag == TYPE_REF_INVALID) return;
    if (expected_tag != TYPE_REF_INSTANCE && actual_tag != TYPE_REF_INSTANCE) return;
    bool matches = expected_tag == actual_tag;
    if (matches && expected_tag == TYPE_REF_INSTANCE)
        matches = prepare_instance_compare(
            node, expected_payload, actual_payload, error_token);
    if (!matches)
        record_min_token_error(
            status,
            valid_token(error_token) ? error_token : 0u,
            ERR_ASSIGN_MISMATCH,
            0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= gParams.n_hir_nodes) return;
    clear_request(node);
    if (!valid_hir(node)) return;

    HirCore core = compact_hir_core[node];
    HirPayload stmt = compact_hir_payload[node];
    if (core.kind != HIR_STMT && core.kind != HIR_LET_STMT &&
        core.kind != HIR_RETURN_STMT && core.kind != HIR_ASSIGN_EXPR)
        return;

    uint expected_tag = TYPE_REF_INVALID;
    uint expected_payload = INVALID;
    uint actual_tag = TYPE_REF_INVALID;
    uint actual_payload = INVALID;
    uint error_token = core.token_start;

    if (stmt.a == HIR_STMT_LET ||
        (core.kind == HIR_STMT && stmt.a == HIR_STMT_CONST))
    {
        type_node_ref(stmt.d, expected_tag, expected_payload);
        if (expected_tag == TYPE_REF_INVALID)
            declaration_ref(stmt.b, expected_tag, expected_payload);
        expression_ref(stmt.c, actual_tag, actual_payload);
        if (valid_hir(stmt.c)) error_token = compact_hir_core[stmt.c].token_start;
    }
    else if (stmt.a == HIR_STMT_ASSIGN)
    {
        expression_ref(stmt.b, expected_tag, expected_payload);
        expression_ref(stmt.c, actual_tag, actual_payload);
        if (valid_hir(stmt.c)) error_token = compact_hir_core[stmt.c].token_start;
    }
    else if (stmt.a == HIR_STMT_RETURN)
    {
        if (!valid_token(core.token_start)) return;
        uint fn = compact_hir_nearest_fn[node];
        if (!valid_hir(fn)) return;
        uint fn_token = compact_hir_payload[fn].b;
        if (!valid_token(fn_token)) return;
        expected_tag = fn_return_ref_tag[fn_token];
        expected_payload = fn_return_ref_payload[fn_token];
        expression_ref(stmt.b, actual_tag, actual_payload);
        if (valid_hir(stmt.b)) error_token = compact_hir_core[stmt.b].token_start;
    }
    else
        return;

    validate_refs(
        node,
        expected_tag,
        expected_payload,
        actual_tag,
        actual_payload,
        error_token);
}
