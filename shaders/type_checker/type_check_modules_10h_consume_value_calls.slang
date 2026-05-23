// GPU HIR-qualified value call consumer.
//
// This pass consumes resolver rows, HIR call records, and function return
// metadata. It does not inspect token kinds, source bytes, helper names, or
// function-body shapes to decide whether a resolved declaration is callable.

import hir_records;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_token_start;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_ref_tag;
StructuredBuffer<uint> call_param_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> module_value_path_call_open;
StructuredBuffer<uint> enclosing_fn;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 4u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint ERR_ASSIGN_MISMATCH = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

uint generic_slot_for_type(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty < TY_GENERIC_BASE + PARAM_CACHE_STRIDE
               ? ty - TY_GENERIC_BASE
               : INVALID;
}

uint array_or_slice_generic_slot(uint ty)
{
    return ty >= TY_ARRAY_BASE + TY_GENERIC_BASE &&
           ty < TY_ARRAY_BASE + TY_GENERIC_BASE + PARAM_CACHE_STRIDE
               ? ty - TY_ARRAY_BASE - TY_GENERIC_BASE
               : INVALID;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint expr_form(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_FORM);
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(node); guard += 1u)
    {
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        uint child = expr_slot(node, HIR_EXPR_RECORD_LEFT);
        if (!valid_node(child))
            return node;
        node = child;
    }
    return node;
}

uint ancestor_with_stmt_kind(uint node, uint target_kind)
{
    [loop]
    for (uint guard = 0u; guard < 128u && valid_node(node); guard += 1u)
    {
        if (hir_stmt_record[stmt_slot(node, 0u)] == target_kind)
            return node;
        node = parent[node];
    }
    return INVALID;
}

uint call_node_for_callee_token(uint callee_i)
{
    if (!valid_token(callee_i))
        return INVALID;
    return call_arg_record[callee_i].z;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;
    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        uint packed = hir_call_arg_parent_call[node];
        if (hir_node_ordinal_node(packed) == call_node &&
            hir_node_ordinal_ordinal(packed) == ordinal)
            return node;
    }
    return INVALID;
}

uint param_cache_index(uint fn_token, uint ordinal)
{
    return fn_token * PARAM_CACHE_STRIDE + ordinal;
}

bool valid_function_decl(uint decl_i, out uint fn_token)
{
    fn_token = INVALID;
    if (decl_i >= gParams.n_hir_nodes)
        return false;

    uint token_i = decl_token_start[decl_i];
    if (!valid_token(token_i) || call_fn_index[token_i] != token_i)
        return false;

    fn_token = token_i;
    return true;
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
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
    {
        uint decl_token = type_instance_decl_token[payload];
        return valid_token(decl_token) ? TY_ENUM_BASE + decl_token : TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return false;
    return dst == src;
}

bool is_struct_type(uint ty)
{
    return ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE;
}

bool actual_ref_for_arg_node(uint arg_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint node = resolve_expr(arg_node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        tag = TYPE_REF_SCALAR;
        payload = TY_BOOL;
        return true;
    }
    if (form == HIR_EXPR_INT)
    {
        tag = TYPE_REF_SCALAR;
        payload = TY_INT;
        return true;
    }

    uint token = form == HIR_EXPR_NAME ? expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN) : INVALID;
    if (!valid_token(token))
        token = hir_token_pos[node];
    if (!valid_token(token))
        return false;

    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        tag = decl_type_ref_tag[decl];
        payload = decl_type_ref_payload[decl];
        return tag != TYPE_REF_INVALID;
    }

    tag = decl_type_ref_tag[token];
    payload = decl_type_ref_payload[token];
    return tag != TYPE_REF_INVALID;
}

bool actual_ref_for_token(uint token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(token))
        return false;

    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        tag = decl_type_ref_tag[decl];
        payload = decl_type_ref_payload[decl];
        return tag != TYPE_REF_INVALID;
    }

    tag = decl_type_ref_tag[token];
    payload = decl_type_ref_payload[token];
    return tag != TYPE_REF_INVALID;
}

uint bound_tag_for_slot(
    uint slot,
    uint b0_tag,
    uint b1_tag,
    uint b2_tag,
    uint b3_tag)
{
    if (slot == 0u)
        return b0_tag;
    if (slot == 1u)
        return b1_tag;
    if (slot == 2u)
        return b2_tag;
    if (slot == 3u)
        return b3_tag;
    return TYPE_REF_INVALID;
}

uint bound_payload_for_slot(
    uint slot,
    uint b0_payload,
    uint b1_payload,
    uint b2_payload,
    uint b3_payload)
{
    if (slot == 0u)
        return b0_payload;
    if (slot == 1u)
        return b1_payload;
    if (slot == 2u)
        return b2_payload;
    if (slot == 3u)
        return b3_payload;
    return INVALID;
}

void set_bound_slot(
    uint slot,
    uint tag,
    uint payload,
    inout uint b0_tag,
    inout uint b0_payload,
    inout uint b1_tag,
    inout uint b1_payload,
    inout uint b2_tag,
    inout uint b2_payload,
    inout uint b3_tag,
    inout uint b3_payload)
{
    if (slot == 0u)
    {
        b0_tag = tag;
        b0_payload = payload;
    }
    else if (slot == 1u)
    {
        b1_tag = tag;
        b1_payload = payload;
    }
    else if (slot == 2u)
    {
        b2_tag = tag;
        b2_payload = payload;
    }
    else if (slot == 3u)
    {
        b3_tag = tag;
        b3_payload = payload;
    }
}

bool refs_equal(uint left_tag, uint left_payload, uint right_tag, uint right_payload)
{
    if (left_tag == TYPE_REF_INVALID || right_tag == TYPE_REF_INVALID)
        return false;
    if (left_tag == right_tag && left_payload == right_payload)
        return true;
    uint left_ty = type_code_for_ref(left_tag, left_payload);
    uint right_ty = type_code_for_ref(right_tag, right_payload);
    return left_ty != TY_UNKNOWN && left_ty == right_ty;
}

bool bind_generic_slot(
    uint slot,
    uint actual_tag,
    uint actual_payload,
    uint error_token,
    inout uint b0_tag,
    inout uint b0_payload,
    inout uint b1_tag,
    inout uint b1_payload,
    inout uint b2_tag,
    inout uint b2_payload,
    inout uint b3_tag,
    inout uint b3_payload)
{
    if (slot == INVALID || slot >= PARAM_CACHE_STRIDE || actual_tag == TYPE_REF_INVALID)
        return true;

    uint old_tag = bound_tag_for_slot(slot, b0_tag, b1_tag, b2_tag, b3_tag);
    uint old_payload =
        bound_payload_for_slot(slot, b0_payload, b1_payload, b2_payload, b3_payload);
    if (old_tag == TYPE_REF_INVALID)
    {
        set_bound_slot(
            slot,
            actual_tag,
            actual_payload,
            b0_tag,
            b0_payload,
            b1_tag,
            b1_payload,
            b2_tag,
            b2_payload,
            b3_tag,
            b3_payload);
        return true;
    }

    if (refs_equal(old_tag, old_payload, actual_tag, actual_payload))
        return true;

    record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(old_tag, old_payload));
    return false;
}

bool unify_leaf_param_ref_with_actual(
    uint param_tag,
    uint param_payload,
    uint actual_tag,
    uint actual_payload,
    uint error_token,
    inout uint b0_tag,
    inout uint b0_payload,
    inout uint b1_tag,
    inout uint b1_payload,
    inout uint b2_tag,
    inout uint b2_payload,
    inout uint b3_tag,
    inout uint b3_payload)
{
    if (param_tag == TYPE_REF_INVALID || actual_tag == TYPE_REF_INVALID)
        return true;

    if (param_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(param_payload) ? type_generic_param_slot_by_token[param_payload]
                                               : INVALID;
        return bind_generic_slot(
            slot,
            actual_tag,
            actual_payload,
            error_token,
            b0_tag,
            b0_payload,
            b1_tag,
            b1_payload,
            b2_tag,
            b2_payload,
            b3_tag,
            b3_payload);
    }

    if (param_tag == TYPE_REF_SCALAR)
    {
        if (assignable(param_payload, type_code_for_ref(actual_tag, actual_payload)))
            return true;
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_payload);
        return false;
    }

    if (refs_equal(param_tag, param_payload, actual_tag, actual_payload))
        return true;

    record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(param_tag, param_payload));
    return false;
}

bool unify_param_ref_with_actual(
    uint param_tag,
    uint param_payload,
    uint actual_tag,
    uint actual_payload,
    uint error_token,
    inout uint b0_tag,
    inout uint b0_payload,
    inout uint b1_tag,
    inout uint b1_payload,
    inout uint b2_tag,
    inout uint b2_payload,
    inout uint b3_tag,
    inout uint b3_payload)
{
    if (param_tag == TYPE_REF_INVALID || actual_tag == TYPE_REF_INVALID)
        return true;

    if (param_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(param_payload) ? type_generic_param_slot_by_token[param_payload]
                                               : INVALID;
        return bind_generic_slot(
            slot,
            actual_tag,
            actual_payload,
            error_token,
            b0_tag,
            b0_payload,
            b1_tag,
            b1_payload,
            b2_tag,
            b2_payload,
            b3_tag,
            b3_payload);
    }

    if (param_tag == TYPE_REF_SCALAR)
    {
        if (assignable(param_payload, type_code_for_ref(actual_tag, actual_payload)))
            return true;
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_payload);
        return false;
    }

    if (param_tag != TYPE_REF_INSTANCE)
        return true;

    if (actual_tag != TYPE_REF_INSTANCE || !valid_token(param_payload) || !valid_token(actual_payload))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(param_tag, param_payload));
        return false;
    }

    uint param_decl = type_instance_decl_token[param_payload];
    uint actual_decl = type_instance_decl_token[actual_payload];
    if (!valid_token(param_decl) || param_decl != actual_decl)
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(param_tag, param_payload));
        return false;
    }

    uint param_count = type_instance_arg_count[param_payload];
    uint actual_count = type_instance_arg_count[actual_payload];
    uint param_start = type_instance_arg_start[param_payload];
    uint actual_start = type_instance_arg_start[actual_payload];
    if (param_count != actual_count)
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(param_tag, param_payload));
        return false;
    }
    if (param_count == 0u)
        return true;
    if (param_start == INVALID || actual_start == INVALID)
        return true;

    [loop]
    for (uint arg_i = 0u; arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        if (arg_i >= param_count)
            break;
        uint param_arg_i = param_start + arg_i;
        uint actual_arg_i = actual_start + arg_i;
        uint p_tag = type_instance_arg_ref_tag[param_arg_i];
        uint p_payload = type_instance_arg_ref_payload[param_arg_i];
        uint a_tag = type_instance_arg_ref_tag[actual_arg_i];
        uint a_payload = type_instance_arg_ref_payload[actual_arg_i];
        if (!unify_leaf_param_ref_with_actual(
                p_tag,
                p_payload,
                a_tag,
                a_payload,
                error_token,
                b0_tag,
                b0_payload,
                b1_tag,
                b1_payload,
                b2_tag,
                b2_payload,
                b3_tag,
                b3_payload))
            return false;
    }

    return true;
}

bool ref_contains_generic(uint tag, uint payload)
{
    if (tag == TYPE_REF_GENERIC_PARAM)
        return true;
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return false;

    uint arg_count = min(type_instance_arg_count[payload], PARAM_CACHE_STRIDE);
    uint arg_start = type_instance_arg_start[payload];
    if (arg_count == 0u || arg_start == INVALID)
        return false;

    [loop]
    for (uint arg_i = 0u; arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        if (arg_i >= arg_count)
            break;
        uint ref_i = arg_start + arg_i;
        if (type_instance_arg_ref_tag[ref_i] == TYPE_REF_GENERIC_PARAM)
            return true;
    }

    return false;
}

bool ref_generics_are_bound(
    uint tag,
    uint payload,
    uint b0_tag,
    uint b1_tag,
    uint b2_tag,
    uint b3_tag)
{
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return bound_tag_for_slot(slot, b0_tag, b1_tag, b2_tag, b3_tag) != TYPE_REF_INVALID;
    }

    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return true;

    uint arg_count = min(type_instance_arg_count[payload], PARAM_CACHE_STRIDE);
    uint arg_start = type_instance_arg_start[payload];
    if (arg_count == 0u)
        return true;
    if (arg_start == INVALID)
        return false;

    [loop]
    for (uint arg_i = 0u; arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        if (arg_i >= arg_count)
            break;
        uint ref_i = arg_start + arg_i;
        uint arg_tag = type_instance_arg_ref_tag[ref_i];
        uint arg_payload = type_instance_arg_ref_payload[ref_i];
        if (arg_tag == TYPE_REF_GENERIC_PARAM)
        {
            uint slot = valid_token(arg_payload) ? type_generic_param_slot_by_token[arg_payload]
                                                 : INVALID;
            if (bound_tag_for_slot(slot, b0_tag, b1_tag, b2_tag, b3_tag) == TYPE_REF_INVALID)
                return false;
        }
        else if (arg_tag == TYPE_REF_INSTANCE && ref_contains_generic(arg_tag, arg_payload))
        {
            return false;
        }
    }

    return true;
}

bool contextual_return_ref_for_call(
    uint owner_token,
    uint call_node,
    out uint tag,
    out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint let_node = ancestor_with_stmt_kind(call_node, STMT_RECORD_KIND_LET);
    if (valid_node(let_node))
    {
        uint decl_token = hir_stmt_record[stmt_slot(let_node, 1u)];
        if (valid_token(decl_token))
        {
            tag = decl_type_ref_tag[decl_token];
            payload = decl_type_ref_payload[decl_token];
            if (tag != TYPE_REF_INVALID)
                return true;
        }
    }

    uint return_node = ancestor_with_stmt_kind(call_node, STMT_RECORD_KIND_RETURN);
    if (valid_node(return_node) && valid_token(owner_token))
    {
        uint encoded_fn = enclosing_fn[owner_token];
        uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
        if (valid_token(fn_token))
        {
            tag = fn_return_ref_tag[fn_token];
            payload = fn_return_ref_payload[fn_token];
            return tag != TYPE_REF_INVALID;
        }
    }

    return false;
}

bool unify_return_leaf_ref_with_context(
    uint ret_tag,
    uint ret_payload,
    uint context_tag,
    uint context_payload,
    uint error_token,
    inout uint b0_tag,
    inout uint b0_payload,
    inout uint b1_tag,
    inout uint b1_payload,
    inout uint b2_tag,
    inout uint b2_payload,
    inout uint b3_tag,
    inout uint b3_payload)
{
    if (ret_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(ret_payload) ? type_generic_param_slot_by_token[ret_payload]
                                             : INVALID;
        return bind_generic_slot(
            slot,
            context_tag,
            context_payload,
            error_token,
            b0_tag,
            b0_payload,
            b1_tag,
            b1_payload,
            b2_tag,
            b2_payload,
            b3_tag,
            b3_payload);
    }

    if (ret_tag == TYPE_REF_SCALAR)
    {
        uint context_ty = type_code_for_ref(context_tag, context_payload);
        if (assignable(context_ty, ret_payload))
            return true;
        record_error(error_token, ERR_ASSIGN_MISMATCH, context_ty * 256u + ret_payload);
        return false;
    }

    if (refs_equal(ret_tag, ret_payload, context_tag, context_payload))
        return true;

    record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(context_tag, context_payload));
    return false;
}

bool unify_return_ref_with_context(
    uint ret_tag,
    uint ret_payload,
    uint context_tag,
    uint context_payload,
    uint error_token,
    inout uint b0_tag,
    inout uint b0_payload,
    inout uint b1_tag,
    inout uint b1_payload,
    inout uint b2_tag,
    inout uint b2_payload,
    inout uint b3_tag,
    inout uint b3_payload)
{
    if (context_tag == TYPE_REF_INVALID)
        return false;

    if (ret_tag != TYPE_REF_INSTANCE)
    {
        return unify_return_leaf_ref_with_context(
            ret_tag,
            ret_payload,
            context_tag,
            context_payload,
            error_token,
            b0_tag,
            b0_payload,
            b1_tag,
            b1_payload,
            b2_tag,
            b2_payload,
            b3_tag,
            b3_payload);
    }

    if (context_tag != TYPE_REF_INSTANCE || !valid_token(ret_payload) || !valid_token(context_payload))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(context_tag, context_payload));
        return false;
    }

    uint ret_decl = type_instance_decl_token[ret_payload];
    uint context_decl = type_instance_decl_token[context_payload];
    if (!valid_token(ret_decl) || ret_decl != context_decl)
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(context_tag, context_payload));
        return false;
    }

    uint ret_count = type_instance_arg_count[ret_payload];
    uint context_count = type_instance_arg_count[context_payload];
    uint ret_start = type_instance_arg_start[ret_payload];
    uint context_start = type_instance_arg_start[context_payload];
    if (ret_count != context_count)
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(context_tag, context_payload));
        return false;
    }
    if (ret_count == 0u)
        return true;
    if (ret_start == INVALID || context_start == INVALID)
        return false;

    uint count = min(ret_count, PARAM_CACHE_STRIDE);
    [loop]
    for (uint arg_i = 0u; arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        if (arg_i >= count)
            break;
        uint ret_arg_i = ret_start + arg_i;
        uint context_arg_i = context_start + arg_i;
        if (!unify_return_leaf_ref_with_context(
                type_instance_arg_ref_tag[ret_arg_i],
                type_instance_arg_ref_payload[ret_arg_i],
                type_instance_arg_ref_tag[context_arg_i],
                type_instance_arg_ref_payload[context_arg_i],
                error_token,
                b0_tag,
                b0_payload,
                b1_tag,
                b1_payload,
                b2_tag,
                b2_payload,
                b3_tag,
                b3_payload))
            return false;
    }

    return true;
}

bool function_needs_generic_validation(uint fn_token)
{
    if (!valid_token(fn_token))
        return false;
    if (is_generic_type(call_return_type[fn_token]) ||
        ref_contains_generic(fn_return_ref_tag[fn_token], fn_return_ref_payload[fn_token]))
        return true;

    uint expected_count = min(call_param_count[fn_token], PARAM_CACHE_STRIDE);
    [loop]
    for (uint ordinal = 0u; ordinal < PARAM_CACHE_STRIDE; ordinal += 1u)
    {
        if (ordinal >= expected_count)
            break;
        uint ref_i = param_cache_index(fn_token, ordinal);
        if (ref_contains_generic(call_param_ref_tag[ref_i], call_param_ref_payload[ref_i]))
            return true;
    }

    return false;
}

bool validate_and_infer_call(uint owner_token, uint fn_token, bool reject_array_generic_call)
{
    uint call_node = call_node_for_callee_token(owner_token);
    if (!valid_node(call_node))
        return true;

    uint expected_count = min(call_param_count[fn_token], PARAM_CACHE_STRIDE);
    uint actual_count = min(call_arg_record[owner_token].w, PARAM_CACHE_STRIDE);
    if (expected_count != actual_count)
    {
        record_error(owner_token, ERR_ASSIGN_MISMATCH, expected_count);
        return false;
    }

    uint b0_tag = TYPE_REF_INVALID;
    uint b0_payload = INVALID;
    uint b1_tag = TYPE_REF_INVALID;
    uint b1_payload = INVALID;
    uint b2_tag = TYPE_REF_INVALID;
    uint b2_payload = INVALID;
    uint b3_tag = TYPE_REF_INVALID;
    uint b3_payload = INVALID;

    [loop]
    for (uint ordinal = 0u; ordinal < PARAM_CACHE_STRIDE; ordinal += 1u)
    {
        if (ordinal >= expected_count)
            break;

        uint param_ref_i = param_cache_index(fn_token, ordinal);
        if (reject_array_generic_call &&
            array_or_slice_generic_slot(call_param_type[param_ref_i]) != INVALID)
        {
            record_error(owner_token, ERR_ASSIGN_MISMATCH, call_param_type[param_ref_i]);
            return false;
        }

        uint param_tag = call_param_ref_tag[param_ref_i];
        uint param_payload = call_param_ref_payload[param_ref_i];
        if (param_tag == TYPE_REF_INVALID)
            continue;

        uint arg_node = call_arg_node_for_call(call_node, ordinal);
        uint actual_tag = TYPE_REF_INVALID;
        uint actual_payload = INVALID;
        if (ordinal == 0u)
        {
            uint first_arg_token = call_arg_record[owner_token].x;
            actual_ref_for_token(first_arg_token, actual_tag, actual_payload);
        }
        if (actual_tag == TYPE_REF_INVALID &&
            !actual_ref_for_arg_node(arg_node, actual_tag, actual_payload))
            continue;

        if (!unify_param_ref_with_actual(
                param_tag,
                param_payload,
                actual_tag,
                actual_payload,
                owner_token,
                b0_tag,
                b0_payload,
                b1_tag,
                b1_payload,
                b2_tag,
                b2_payload,
                b3_tag,
                b3_payload))
            return false;
    }

    uint ret_slot = INVALID;
    uint ret_ref_tag = fn_return_ref_tag[fn_token];
    uint ret_ref_payload = fn_return_ref_payload[fn_token];
    if (reject_array_generic_call &&
        array_or_slice_generic_slot(call_return_type[fn_token]) != INVALID)
    {
        record_error(owner_token, ERR_ASSIGN_MISMATCH, call_return_type[fn_token]);
        return false;
    }
    if (ret_ref_tag == TYPE_REF_GENERIC_PARAM)
        ret_slot = valid_token(ret_ref_payload) ? type_generic_param_slot_by_token[ret_ref_payload] : INVALID;
    if (ret_slot == INVALID)
        ret_slot = generic_slot_for_type(call_return_type[fn_token]);
    if (ret_slot != INVALID)
    {
        uint bound_ret_tag = bound_tag_for_slot(ret_slot, b0_tag, b1_tag, b2_tag, b3_tag);
        uint bound_ret_payload =
            bound_payload_for_slot(ret_slot, b0_payload, b1_payload, b2_payload, b3_payload);
        uint inferred_ty = type_code_for_ref(bound_ret_tag, bound_ret_payload);
        if (inferred_ty != TY_UNKNOWN)
            call_return_type[owner_token] = inferred_ty;
    }
    else if (ret_ref_tag == TYPE_REF_INSTANCE && ref_contains_generic(ret_ref_tag, ret_ref_payload))
    {
        uint context_tag = TYPE_REF_INVALID;
        uint context_payload = INVALID;
        bool has_context = contextual_return_ref_for_call(
            owner_token,
            call_node,
            context_tag,
            context_payload);
        if (has_context &&
            !unify_return_ref_with_context(
                ret_ref_tag,
                ret_ref_payload,
                context_tag,
                context_payload,
                owner_token,
                b0_tag,
                b0_payload,
                b1_tag,
                b1_payload,
                b2_tag,
                b2_payload,
                b3_tag,
                b3_payload))
        {
            return false;
        }
        if (!has_context &&
            !ref_generics_are_bound(ret_ref_tag, ret_ref_payload, b0_tag, b1_tag, b2_tag, b3_tag))
        {
            record_error(owner_token, ERR_ASSIGN_MISMATCH, type_code_for_ref(ret_ref_tag, ret_ref_payload));
            return false;
        }

        uint inferred_instance_ty = call_return_type[fn_token];
        if (inferred_instance_ty == TY_UNKNOWN || is_generic_type(inferred_instance_ty))
            inferred_instance_ty = type_code_for_ref(ret_ref_tag, ret_ref_payload);
        if (is_struct_type(inferred_instance_ty))
        {
            record_error(owner_token, ERR_ASSIGN_MISMATCH, inferred_instance_ty);
            return false;
        }
        if (inferred_instance_ty != TY_UNKNOWN)
            call_return_type[owner_token] = inferred_instance_ty;
    }

    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;

    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token) || module_value_path_call_open[owner_token] == INVALID)
        return;

    if (!valid_node(call_node_for_callee_token(owner_token)))
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint fn_token;
    if (!valid_function_decl(resolved_value_decl[path_i], fn_token))
        return;

    uint ret_ty = call_return_type[owner_token];
    bool qualified_call = true;
    if (function_needs_generic_validation(fn_token) &&
        !validate_and_infer_call(owner_token, fn_token, qualified_call))
    {
        module_value_path_status[owner_token] = INVALID;
        return;
    }

    if (call_return_type[owner_token] != TY_UNKNOWN)
        ret_ty = call_return_type[owner_token];
    else if (ret_ty == TY_UNKNOWN)
    {
        uint decl_ret_ty = call_return_type[fn_token];
        if (!is_generic_type(decl_ret_ty))
            ret_ty = decl_ret_ty;
    }

    call_fn_index[owner_token] = fn_token;
    if (ret_ty != TY_UNKNOWN)
        call_return_type[owner_token] = ret_ty;
    module_value_path_status[owner_token] = INVALID;
}
