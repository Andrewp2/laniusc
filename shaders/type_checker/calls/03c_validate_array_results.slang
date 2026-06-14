// HIR-record array call-result validation.
//
// This pass runs after bounded generic array call inference. It keeps
// array-valued call results length-aware by comparing the annotated destination
// declaration's array instance with either the callee's declared return array
// instance or the declaration-backed actual array argument instance. It consumes
// HIR statement/call records, parser-published expression-result roots, and
// type-instance refs; it does not inspect source bytes, token spelling, helper
// names, or callee function bodies. Over-width call/parameter windows fail
// closed before bounded cache slots are consumed.

import hir_records;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_node;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_ref_tag;
StructuredBuffer<uint> call_param_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> method_call_name_id;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;

static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint PARAM_CACHE_STRIDE = 4u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) || hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : hir_token_pos[node];
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

bool is_symbolic_array_type(uint ty)
{
    return ty == TY_ARRAY_BASE + TY_UNKNOWN ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;

    uint token = hir_token_pos[callee_node];
    return valid_token(token) ? token : INVALID;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;
    return call_arg_node[call_node * PARAM_CACHE_STRIDE + ordinal];
}

uint first_call_arg_name_token(uint callee_token, uint call_node)
{
    uint arg_node = call_arg_node_for_call(call_node, 0u);
    uint arg_node_token = name_token_for_expr(arg_node);
    if (valid_token(arg_node_token))
        return arg_node_token;

    if (valid_token(callee_token))
    {
        uint arg_token = call_arg_record[callee_token].x;
        if (valid_token(arg_token))
            return arg_token;
    }

    return INVALID;
}

uint call_arg_count_for_callee(uint callee_token, uint call_node)
{
    if (!valid_token(callee_token))
        return 0u;
    uint record_count = call_arg_record[callee_token].w;
    if (!valid_node(call_node))
        return record_count;
    return max(record_count, hir_call_arg_count[call_node]);
}

bool call_window_fits_cache(uint callee_token, uint call_node)
{
    uint fn_token = valid_token(callee_token) ? call_fn_index[callee_token] : INVALID;
    if (!valid_token(fn_token))
        return true;

    uint param_count = call_param_count[fn_token];
    uint arg_count = call_arg_count_for_callee(callee_token, call_node);
    if (param_count <= PARAM_CACHE_STRIDE && arg_count <= PARAM_CACHE_STRIDE)
        return true;

    call_return_type[callee_token] = TY_UNKNOWN;
    record_min_token_error(
        status,
        callee_token,
        ERR_CALL_MISMATCH,
        param_count * 256u + arg_count);
    return false;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    if (type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;

    uint len_kind = type_instance_len_kind[payload];
    if (len_kind != TYPE_LEN_LITERAL && len_kind != TYPE_LEN_CONST_PARAM)
        return INVALID;
    return payload;
}

uint array_instance_from_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl_token],
        decl_type_ref_payload[decl_token]);
}

uint array_instance_from_name_token(uint name_token)
{
    return valid_token(name_token) ? array_instance_from_decl_token(visible_decl[name_token])
                                   : INVALID;
}

uint array_instance_from_callee_return(uint callee_token)
{
    if (!valid_token(callee_token))
        return INVALID;

    uint decl_token = call_fn_index[callee_token];
    if (!valid_token(decl_token))
        decl_token = visible_decl[callee_token];
    if (!valid_token(decl_token))
        decl_token = callee_token;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[decl_token],
        fn_return_ref_payload[decl_token]);
}

uint param_cache_index(uint fn_token, uint ordinal)
{
    return fn_token * PARAM_CACHE_STRIDE + ordinal;
}

uint array_instance_from_call_param(uint callee_token, uint ordinal)
{
    if (!valid_token(callee_token) || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;
    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token) || ordinal >= call_param_count[fn_token])
        return INVALID;
    uint ref_i = param_cache_index(fn_token, ordinal);
    return bounded_array_instance_from_ref(
        call_param_ref_tag[ref_i],
        call_param_ref_payload[ref_i]);
}

bool same_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    if (lhs_tag == TYPE_REF_SCALAR || rhs_tag == TYPE_REF_SCALAR)
        return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
    if (lhs_tag == TYPE_REF_GENERIC_PARAM && rhs_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint lhs_slot = valid_token(lhs_payload) ? type_generic_param_slot_by_token[lhs_payload] : INVALID;
        uint rhs_slot = valid_token(rhs_payload) ? type_generic_param_slot_by_token[rhs_payload] : INVALID;
        return lhs_slot != INVALID && lhs_slot == rhs_slot;
    }
    return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
}

bool concrete_array_elem_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return true;
    if (tag == TYPE_REF_GENERIC_PARAM)
        return false;
    return tag == TYPE_REF_INSTANCE && valid_token(payload);
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    return TY_UNKNOWN;
}

uint array_type_code_from_instance(uint instance)
{
    if (!valid_token(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return TY_UNKNOWN;
    uint elem_ty = type_code_for_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
    return elem_ty == TY_UNKNOWN ? TY_UNKNOWN : TY_ARRAY_BASE + elem_ty;
}

bool same_array_len(uint lhs, uint rhs)
{
    uint lhs_kind = type_instance_len_kind[lhs];
    uint rhs_kind = type_instance_len_kind[rhs];
    if (lhs_kind != rhs_kind)
        return false;
    if (lhs_kind == TYPE_LEN_LITERAL)
        return type_instance_len_payload[lhs] == type_instance_len_payload[rhs];
    if (lhs_kind == TYPE_LEN_CONST_PARAM)
    {
        uint lhs_payload = type_instance_len_payload[lhs];
        uint rhs_payload = type_instance_len_payload[rhs];
        uint lhs_slot = valid_token(lhs_payload) ? type_const_param_slot_by_token[lhs_payload] : INVALID;
        uint rhs_slot = valid_token(rhs_payload) ? type_const_param_slot_by_token[rhs_payload] : INVALID;
        return lhs_slot != INVALID && lhs_slot == rhs_slot;
    }
    return false;
}

bool concrete_bounded_array_instance(uint instance)
{
    if (!valid_token(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return false;
    if (type_instance_len_kind[instance] != TYPE_LEN_LITERAL)
        return false;
    return concrete_array_elem_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

bool same_bounded_array_instance(uint lhs, uint rhs)
{
    if (!valid_token(lhs) || !valid_token(rhs))
        return false;
    if (type_instance_kind[lhs] != TYPE_INSTANCE_ARRAY ||
        type_instance_kind[rhs] != TYPE_INSTANCE_ARRAY)
        return false;
    if (!same_array_len(lhs, rhs))
        return false;
    return same_type_ref(
        type_instance_elem_ref_tag[lhs],
        type_instance_elem_ref_payload[lhs],
        type_instance_elem_ref_tag[rhs],
        type_instance_elem_ref_payload[rhs]);
}

uint prior_matching_generic_array_arg_instance_slot(
    uint callee_token,
    uint call_node,
    uint ordinal,
    uint expected_instance,
    uint prior)
{
    if (prior >= ordinal)
        return INVALID;

    uint prior_expected = array_instance_from_call_param(callee_token, prior);
    if (!same_bounded_array_instance(expected_instance, prior_expected))
        return INVALID;

    uint prior_arg_node = call_arg_node_for_call(call_node, prior);
    uint prior_actual =
        array_instance_from_name_token(name_token_for_expr(prior_arg_node));
    return concrete_bounded_array_instance(prior_actual) ? prior_actual : INVALID;
}

uint prior_matching_generic_array_arg_instance(
    uint callee_token,
    uint call_node,
    uint ordinal,
    uint expected_instance)
{
    uint prior_actual = prior_matching_generic_array_arg_instance_slot(
        callee_token, call_node, ordinal, expected_instance, 0u);
    if (prior_actual != INVALID)
        return prior_actual;
    prior_actual = prior_matching_generic_array_arg_instance_slot(
        callee_token, call_node, ordinal, expected_instance, 1u);
    if (prior_actual != INVALID)
        return prior_actual;
    prior_actual = prior_matching_generic_array_arg_instance_slot(
        callee_token, call_node, ordinal, expected_instance, 2u);
    if (prior_actual != INVALID)
        return prior_actual;
    prior_actual = prior_matching_generic_array_arg_instance_slot(
        callee_token, call_node, ordinal, expected_instance, 3u);
    if (prior_actual != INVALID)
        return prior_actual;

    return INVALID;
}

void validate_array_call_arg_slot(uint slot)
{
    uint call_node = slot / PARAM_CACHE_STRIDE;
    uint ordinal = slot - call_node * PARAM_CACHE_STRIDE;
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;
    if (method_call_name_id[callee_token] != INVALID)
        return;

    uint expected_instance = array_instance_from_call_param(callee_token, ordinal);
    if (expected_instance == INVALID)
        return;
    if (!call_window_fits_cache(callee_token, call_node))
        return;

    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    uint actual_instance = array_instance_from_name_token(name_token_for_expr(arg_node));
    if (concrete_bounded_array_instance(expected_instance))
    {
        if (same_bounded_array_instance(expected_instance, actual_instance))
            return;

        record_min_token_error(
            status,
            callee_token,
            ERR_ASSIGN_MISMATCH,
            TY_ARRAY_BASE * 256u + TY_UNKNOWN);
        return;
    }

    uint prior_instance = prior_matching_generic_array_arg_instance(
        callee_token,
        call_node,
        ordinal,
        expected_instance);
    if (prior_instance == INVALID)
        return;
    if (concrete_bounded_array_instance(actual_instance) &&
        same_bounded_array_instance(prior_instance, actual_instance))
        return;

    record_min_token_error(
        status,
        callee_token,
        ERR_ASSIGN_MISMATCH,
        TY_ARRAY_BASE * 256u + TY_UNKNOWN);
}

void validate_array_call_let(uint node)
{
    if (!valid_node(node) ||
        hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_LET)
        return;

    uint decl_token = hir_stmt_record[stmt_slot(node, 1u)];
    uint expected_ty = valid_token(decl_token) ? visible_type[decl_token] : TY_UNKNOWN;
    uint expected_instance = array_instance_from_decl_token(decl_token);
    if (expected_instance != INVALID)
    {
        uint instance_ty = array_type_code_from_instance(expected_instance);
        if (instance_ty != TY_UNKNOWN)
            expected_ty = instance_ty;
    }
    if (expected_instance == INVALID && !is_array_type(expected_ty))
        return;

    uint expr_node = hir_stmt_record[stmt_slot(node, 2u)];
    uint call_node = resolve_expr(expr_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;
    if (method_call_name_id[callee_token] != INVALID)
        return;
    if (!call_window_fits_cache(callee_token, call_node))
        return;
    if (!is_array_type(call_return_type[callee_token]))
        return;

    uint actual_ty = call_return_type[callee_token];
    bool specialize_symbolic_result = is_symbolic_array_type(actual_ty);
    if (specialize_symbolic_result && expected_ty != TY_UNKNOWN)
        call_return_type[callee_token] = expected_ty;
    if (expected_instance == INVALID)
        return;

    uint declared_instance = array_instance_from_callee_return(callee_token);
    if (declared_instance != INVALID &&
        same_bounded_array_instance(expected_instance, declared_instance))
    {
        return;
    }

    uint actual_instance = INVALID;
    if (declared_instance != INVALID)
    {
        actual_instance = prior_matching_generic_array_arg_instance(
            callee_token,
            call_node,
            PARAM_CACHE_STRIDE,
            declared_instance);
    }
    else if (specialize_symbolic_result)
    {
        actual_instance =
            array_instance_from_name_token(first_call_arg_name_token(callee_token, call_node));
    }
    if (actual_instance != INVALID &&
        same_bounded_array_instance(expected_instance, actual_instance))
    {
        return;
    }

    record_min_token_error(
        status,
        valid_token(callee_token) ? callee_token : decl_token,
        ERR_ASSIGN_MISMATCH,
        TY_ARRAY_BASE * 256u + actual_ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    validate_array_call_let(node);
    validate_array_call_arg_slot(node);
}
