// Resolve direct function calls and bounded scalar generic return types.
//
// This pass consumes parser-owned HIR call/argument/expression records plus
// visible declaration/type records. It must run after `type_check_scope_hir`
// publishes visible_type for declarations and uses. It does not inspect token
// kinds, token neighborhoods, source bytes, helper names, or function bodies.

import generated_parse_production_ids;
import gpu_index;
import hir_records;
import lookup;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_node;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_ref_tag;
StructuredBuffer<uint> call_param_ref_payload;
StructuredBuffer<uint> function_lookup_key;
StructuredBuffer<uint> function_lookup_fn;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_token_start;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_PATH_EXPR = 33u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[noinline]
uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[noinline]
uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

[noinline]
uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[noinline]
bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

[noinline]
bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

[noinline]
uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

[noinline]
void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

[noinline]
bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

[noinline]
bool is_symbolic_array_type(uint ty)
{
    return ty == TY_ARRAY_BASE + TY_UNKNOWN ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

[noinline]
uint expr_record_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

[noinline]
uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

[noinline]
uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

[noinline]
uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

[noinline]
uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token];
}

[noinline]
uint scalar_type_for_literal_prod(uint prod)
{
    if (prod == PROD_INT)
        return TY_INT;
    if (prod == PROD_TRUE || prod == PROD_FALSE)
        return TY_BOOL;
    if (prod == PROD_FLOAT)
        return TY_FLOAT;
    if (prod == PROD_STRING)
        return TY_STRING;
    if (prod == PROD_CHAR)
        return TY_CHAR;
    return TY_UNKNOWN;
}

[noinline]
uint call_node_for_callee_token(uint callee_i)
{
    if (!valid_token(callee_i))
        return INVALID;
    return call_arg_record[callee_i].z;
}

[noinline]
bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = hir_call_callee_node[call_node];
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR;
}

[noinline]
bool call_record_is_qualified_path_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node) || hir_kind[callee_node] != HIR_PATH_EXPR)
        return false;
    uint start = hir_token_pos[callee_node];
    uint end = hir_token_end[callee_node];
    return start != INVALID && end != INVALID && end > start + 1u;
}

[noinline]
uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
    {
        uint call_token = hir_token_pos[call_node];
        return valid_token(call_token) ? call_token : INVALID;
    }

    uint callee_token = expr_value_token(callee_node);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[call_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

[noinline]
uint call_arg_count_for_callee(uint callee_i)
{
    if (!valid_token(callee_i))
        return 0u;
    uint4 record = call_arg_record[callee_i];
    uint call_node = record.z;
    if (!valid_node(call_node))
        return record.w;
    return max(record.w, hir_call_arg_count[call_node]);
}

[noinline]
uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;
    return call_arg_node[call_node * PARAM_CACHE_STRIDE + ordinal];
}

[noinline]
uint direct_function_lookup_slot(uint key)
{
    uint cap = lookup_capacity();
    if (cap == 0u || key == INVALID)
        return INVALID;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = open_address_probe_slot(key, cap, probe);
        uint row_key = function_lookup_key[slot];
        if (row_key == key)
            return slot;
        if (row_key == INVALID)
            return INVALID;
    }
    return INVALID;
}

[noinline]
bool function_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN || item_kind == HIR_ITEM_KIND_EXTERN_FN;
}

[noinline]
uint fallback_function_decl_by_name_id(uint key)
{
    if (key == INVALID)
        return INVALID;

    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        if (!function_item_kind(hir_item_kind[node]))
            continue;
        uint name_token = hir_item_name_token[node];
        if (!valid_token(name_token) || name_id_by_token[name_token] != key)
            continue;
        uint fn_token = hir_token_pos[node];
        if (valid_token(fn_token) && call_fn_index[fn_token] == fn_token)
            return fn_token;
    }
    return INVALID;
}

[noinline]
uint find_function_decl_by_name_id(uint name_i)
{
    if (!valid_token(name_i))
        return INVALID;

    uint key = name_id_by_token[name_i];
    uint slot = direct_function_lookup_slot(key);
    if (slot == INVALID)
        return INVALID;

    uint fn_i = function_lookup_fn[slot];
    if (valid_token(fn_i) && function_lookup_key[slot] == key)
        return fn_i;
    return fallback_function_decl_by_name_id(key);
}

uint path_node_for_call(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;
    if (hir_kind[callee_node] == HIR_PATH_EXPR)
        return callee_node;
    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && hir_kind[child] == HIR_PATH_EXPR)
            return child;
    }
    return INVALID;
}

uint path_id_for_call(uint call_node)
{
    uint path_node = path_node_for_call(call_node);
    if (!valid_node(path_node))
        return INVALID;
    uint path_i = path_id_by_owner_hir[path_node];
    return path_i < gParams.n_hir_nodes ? path_i : INVALID;
}

bool path_is_qualified(uint path_i)
{
    return path_i != INVALID && path_i < gParams.n_hir_nodes && path_segment_count[path_i] > 1u;
}

uint resolved_function_for_call_path(uint call_node)
{
    uint path_i = path_id_for_call(call_node);
    if (path_i == INVALID)
        return INVALID;
    if (path_owner_module_id[path_i] == INVALID)
        return INVALID;

    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return INVALID;
    uint decl_i = resolved_value_decl[path_i];
    if (decl_i >= gParams.n_tokens)
        return INVALID;
    uint fn_i = decl_token_start[decl_i];
    return valid_token(fn_i) && call_fn_index[fn_i] == fn_i ? fn_i : INVALID;
}

[noinline]
uint direct_call_return_type_direct(uint callee_i);
[noinline]
uint inferred_generic_return_type_from_args(uint callee_i, uint fn_i, uint ret_ty);
[noinline]
uint actual_instance_or_call_return_arg_type(
    uint call_node,
    uint ordinal,
    uint expected_instance,
    uint instance_arg_ordinal);

[noinline]
uint direct_node_type_no_nested_call(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = scalar_type_for_literal_prod(node_kind[node]);
    if (lit != TY_UNKNOWN)
        return lit;

    uint token = hir_token_pos[node];
    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        uint value_token = expr_value_token(node);
        if (valid_token(value_token))
            token = value_token;
        return visible_type_for_token(token);
    }

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[node];
        return visible_type_for_token(member_token);
    }

    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR)
    {
        uint head_node = hir_struct_lit_head_node[node];
        return valid_node(head_node) ? visible_type_for_token(hir_token_pos[head_node])
                                     : TY_UNKNOWN;
    }

    if (hir_kind[node] == HIR_INDEX_EXPR || hir_kind[node] == HIR_MATCH_EXPR)
        return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;

    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint callee_token = callee_token_for_hir_call(node);
        if (!valid_token(callee_token))
            callee_token = hir_token_pos[node];
        return valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

[noinline]
uint expr_type_no_nested_call(uint result_node)
{
    uint node = resolve_expr(result_node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint direct_ty = direct_node_type_no_nested_call(node);
    if (direct_ty != TY_UNKNOWN)
        return direct_ty;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token = expr_value_token(node);
        if (!valid_token(token))
            token = hir_token_pos[node];
        return visible_type_for_token(token);
    }

    if (form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ ||
        form == HIR_EXPR_NE ||
        form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE ||
        form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR)
        return TY_BOOL;

    if (form == HIR_EXPR_NEG ||
        form == HIR_EXPR_ADD ||
        form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL ||
        form == HIR_EXPR_MOD ||
        form == HIR_EXPR_DIV ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
}

[noinline]
uint direct_node_type(uint node)
{
    uint ty = direct_node_type_no_nested_call(node);
    if (ty != TY_UNKNOWN)
        return ty;

    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return TY_UNKNOWN;

    uint callee_token = callee_token_for_hir_call(node);
    return valid_token(callee_token) ? direct_call_return_type_direct(callee_token)
                                     : TY_UNKNOWN;
}

[noinline]
uint expr_type(uint result_node)
{
    uint node = resolve_expr(result_node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint ty = direct_node_type(node);
    if (ty != TY_UNKNOWN)
        return ty;

    return expr_type_no_nested_call(node);
}

[noinline]
uint arg_expr_type_no_nested_call(uint call_node, uint ordinal)
{
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    return expr_type_no_nested_call(arg_node);
}

[noinline]
uint arg_expr_type(uint call_node, uint ordinal)
{
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    return expr_type(arg_node);
}

[noinline]
uint param_ref_index(uint fn_i, uint ordinal)
{
    return fn_i * PARAM_CACHE_STRIDE + ordinal;
}

[noinline]
uint instance_arg_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_start[instance_i];
    return start == INVALID ? INVALID : start + slot;
}

[noinline]
uint generic_slot_for_type_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_GENERIC_PARAM || !valid_token(payload))
        return INVALID;
    return type_generic_param_slot_by_token[payload];
}

[noinline]
uint leaf_type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    uint slot = generic_slot_for_type_ref(tag, payload);
    return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
}

[noinline]
bool instance_arg_ref(uint instance_i, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i) || ordinal >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;
    if (type_instance_kind[instance_i] != TYPE_INSTANCE_NAMED)
        return false;
    if (ordinal >= type_instance_arg_count[instance_i])
        return false;

    uint ref_i = instance_arg_ref_index(instance_i, ordinal);
    if (ref_i == INVALID)
        return false;

    tag = type_instance_arg_ref_tag[ref_i];
    payload = type_instance_arg_ref_payload[ref_i];
    return tag != TYPE_REF_INVALID;
}

[noinline]
bool param_instance_ref(uint fn_i, uint ordinal, out uint instance_i)
{
    instance_i = INVALID;
    if (!valid_token(fn_i) || ordinal >= PARAM_CACHE_STRIDE)
        return false;

    uint ref_i = param_ref_index(fn_i, ordinal);
    if (call_param_ref_tag[ref_i] != TYPE_REF_INSTANCE)
        return false;

    uint payload = call_param_ref_payload[ref_i];
    if (!valid_token(payload) || type_instance_kind[payload] != TYPE_INSTANCE_NAMED)
        return false;

    instance_i = payload;
    return true;
}

[noinline]
uint param_instance_generic_slot(uint fn_i, uint ordinal, uint instance_arg_ordinal)
{
    uint instance_i;
    if (!param_instance_ref(fn_i, ordinal, instance_i))
        return INVALID;

    uint tag;
    uint payload;
    if (!instance_arg_ref(instance_i, instance_arg_ordinal, tag, payload))
        return INVALID;

    return generic_slot_for_type_ref(tag, payload);
}

[noinline]
uint direct_name_expr_token(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node))
        return INVALID;
    if (expr_form(node) != HIR_EXPR_NAME && hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;
    uint token = expr_value_token(node);
    if (!valid_token(token))
        token = hir_token_pos[node];
    return valid_token(token) ? token : INVALID;
}

[noinline]
bool read_decl_type_ref(uint token_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(token_i))
        return false;

    uint ref_token = token_i;
    uint decl = visible_decl[token_i];
    if (valid_token(decl))
        ref_token = decl;

    tag = decl_type_ref_tag[ref_token];
    payload = decl_type_ref_payload[ref_token];
    if (tag != TYPE_REF_INVALID)
        return true;

    if (ref_token != token_i)
    {
        tag = decl_type_ref_tag[token_i];
        payload = decl_type_ref_payload[token_i];
    }
    return tag != TYPE_REF_INVALID;
}

[noinline]
bool arg_decl_type_ref(uint call_node, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    uint token = direct_name_expr_token(arg_node);
    return read_decl_type_ref(token, tag, payload);
}

[noinline]
bool same_named_instance_decl(uint expected_instance, uint actual_instance)
{
    if (!valid_token(expected_instance) || !valid_token(actual_instance))
        return false;
    if (type_instance_kind[expected_instance] != TYPE_INSTANCE_NAMED ||
        type_instance_kind[actual_instance] != TYPE_INSTANCE_NAMED)
        return false;

    uint expected_decl = type_instance_decl_token[expected_instance];
    uint actual_decl = type_instance_decl_token[actual_instance];
    return valid_token(expected_decl) &&
           valid_token(actual_decl) &&
           expected_decl == actual_decl;
}

[noinline]
bool actual_arg_decl_instance_ref(uint call_node, uint ordinal, out uint actual_instance)
{
    actual_instance = INVALID;
    uint tag;
    uint payload;
    if (!arg_decl_type_ref(call_node, ordinal, tag, payload))
        return false;
    if (tag != TYPE_REF_INSTANCE ||
        !valid_token(payload) ||
        type_instance_kind[payload] != TYPE_INSTANCE_NAMED)
        return false;
    actual_instance = payload;
    return true;
}

[noinline]
bool actual_arg_call_return_instance_ref(uint call_node, uint ordinal, out uint actual_instance)
{
    actual_instance = INVALID;
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    uint actual_call_node = resolve_expr(arg_node);
    if (!valid_node(actual_call_node) || hir_kind[actual_call_node] != HIR_CALL_EXPR)
        return false;

    uint actual_callee = callee_token_for_hir_call(actual_call_node);
    uint actual_fn = find_function_decl_by_name_id(actual_callee);
    if (!valid_token(actual_fn))
        return false;

    uint return_instance = call_return_type_token[actual_fn];
    if (!valid_token(return_instance) ||
        type_instance_kind[return_instance] != TYPE_INSTANCE_NAMED)
        return false;
    actual_instance = return_instance;
    return true;
}

[noinline]
bool actual_arg_instance_ref(uint call_node, uint ordinal, out uint actual_instance)
{
    if (actual_arg_decl_instance_ref(call_node, ordinal, actual_instance))
        return true;
    return actual_arg_call_return_instance_ref(call_node, ordinal, actual_instance);
}

[noinline]
bool concrete_leaf_instance_arg_supported(uint instance_i, uint ordinal)
{
    uint tag;
    uint payload;
    if (!instance_arg_ref(instance_i, ordinal, tag, payload))
        return true;
    return tag == TYPE_REF_SCALAR;
}

[noinline]
bool concrete_leaf_instance_supported(uint instance_i)
{
    if (!valid_token(instance_i) ||
        type_instance_arg_count[instance_i] > TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;
    if (!concrete_leaf_instance_arg_supported(instance_i, 0u))
        return false;
    if (!concrete_leaf_instance_arg_supported(instance_i, 1u))
        return false;
    if (!concrete_leaf_instance_arg_supported(instance_i, 2u))
        return false;
    return concrete_leaf_instance_arg_supported(instance_i, 3u);
}

[noinline]
bool direct_call_instance_arg_relation_supported(uint instance_i, uint ordinal)
{
    if (!valid_token(instance_i))
        return false;

    uint arg_count = type_instance_arg_count[instance_i];
    if (ordinal >= arg_count)
        return true;
    if (ordinal >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;

    uint ref_i = instance_arg_ref_index(instance_i, ordinal);
    if (ref_i == INVALID)
        return false;

    uint tag = type_instance_arg_ref_tag[ref_i];
    uint payload = type_instance_arg_ref_payload[ref_i];
    if (tag == TYPE_REF_INVALID ||
        tag == TYPE_REF_ERROR ||
        payload == INVALID)
        return false;

    if (tag == TYPE_REF_SCALAR)
        return payload != TY_UNKNOWN;
    if (tag == TYPE_REF_GENERIC_PARAM)
        return generic_slot_for_type_ref(tag, payload) != INVALID;
    return false;
}

[noinline]
bool direct_call_instance_args_supported(uint instance_i)
{
    if (!valid_token(instance_i) ||
        type_instance_arg_count[instance_i] > TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;
    if (!direct_call_instance_arg_relation_supported(instance_i, 0u))
        return false;
    if (!direct_call_instance_arg_relation_supported(instance_i, 1u))
        return false;
    if (!direct_call_instance_arg_relation_supported(instance_i, 2u))
        return false;
    return direct_call_instance_arg_relation_supported(instance_i, 3u);
}

[noinline]
uint call_arg_error_token(uint call_node, uint arg_i, uint callee_i)
{
    uint arg_node = call_arg_node_for_call(call_node, arg_i);
    return valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
}

[noinline]
bool concrete_leaf_instance_arg_matches(
    uint call_node,
    uint arg_i,
    uint expected_instance,
    uint ordinal)
{
    uint expected_tag;
    uint expected_payload;
    if (!instance_arg_ref(expected_instance, ordinal, expected_tag, expected_payload))
        return true;
    if (expected_tag != TYPE_REF_SCALAR)
        return true;

    uint actual_ty = actual_instance_or_call_return_arg_type(
        call_node,
        arg_i,
        expected_instance,
        ordinal);
    return actual_ty != TY_UNKNOWN && actual_ty == expected_payload;
}

[noinline]
bool check_concrete_instance_argument(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_i,
    uint param_ty)
{
    uint expected_instance;
    if (!param_instance_ref(fn_i, arg_i, expected_instance))
        return true;

    uint error_token = call_arg_error_token(call_node, arg_i, callee_i);
    if (!concrete_leaf_instance_supported(expected_instance))
        return true;

    if (!direct_call_instance_args_supported(expected_instance))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_ty);
        return false;
    }

    uint actual_instance;
    if (!actual_arg_instance_ref(call_node, arg_i, actual_instance))
        return true;

    if (!same_named_instance_decl(expected_instance, actual_instance) ||
        type_instance_arg_count[expected_instance] != type_instance_arg_count[actual_instance])
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_ty);
        return false;
    }

    if (!concrete_leaf_instance_arg_matches(call_node, arg_i, expected_instance, 0u) ||
        !concrete_leaf_instance_arg_matches(call_node, arg_i, expected_instance, 1u) ||
        !concrete_leaf_instance_arg_matches(call_node, arg_i, expected_instance, 2u) ||
        !concrete_leaf_instance_arg_matches(call_node, arg_i, expected_instance, 3u))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_ty);
        return false;
    }
    return true;
}

[noinline]
uint actual_instance_arg_type(
    uint call_node,
    uint ordinal,
    uint expected_instance,
    uint instance_arg_ordinal)
{
    uint actual_tag;
    uint actual_payload;
    if (!arg_decl_type_ref(call_node, ordinal, actual_tag, actual_payload))
        return TY_UNKNOWN;
    if (actual_tag != TYPE_REF_INSTANCE ||
        !same_named_instance_decl(expected_instance, actual_payload))
        return TY_UNKNOWN;

    uint arg_tag;
    uint arg_payload;
    if (!instance_arg_ref(actual_payload, instance_arg_ordinal, arg_tag, arg_payload))
        return TY_UNKNOWN;
    return leaf_type_code_for_ref(arg_tag, arg_payload);
}

[noinline]
uint actual_call_return_instance_arg_type(
    uint call_node,
    uint ordinal,
    uint expected_instance,
    uint instance_arg_ordinal)
{
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    uint actual_call_node = resolve_expr(arg_node);
    if (!valid_node(actual_call_node) || hir_kind[actual_call_node] != HIR_CALL_EXPR)
        return TY_UNKNOWN;

    uint actual_callee = callee_token_for_hir_call(actual_call_node);
    uint actual_fn = find_function_decl_by_name_id(actual_callee);
    if (!valid_token(actual_fn))
        return TY_UNKNOWN;

    uint return_instance = call_return_type_token[actual_fn];
    if (!same_named_instance_decl(expected_instance, return_instance))
        return TY_UNKNOWN;

    uint arg_tag;
    uint arg_payload;
    if (!instance_arg_ref(return_instance, instance_arg_ordinal, arg_tag, arg_payload))
        return TY_UNKNOWN;

    if (arg_tag != TYPE_REF_GENERIC_PARAM)
        return leaf_type_code_for_ref(arg_tag, arg_payload);

    uint slot = generic_slot_for_type_ref(arg_tag, arg_payload);
    if (slot == INVALID)
        return TY_UNKNOWN;
    return inferred_generic_return_type_from_args(actual_callee, actual_fn, TY_GENERIC_BASE + slot);
}

[noinline]
uint actual_call_return_instance_arg_type_no_nested_generic_inference(
    uint call_node,
    uint ordinal,
    uint expected_instance,
    uint instance_arg_ordinal)
{
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    uint actual_call_node = resolve_expr(arg_node);
    if (!valid_node(actual_call_node) || hir_kind[actual_call_node] != HIR_CALL_EXPR)
        return TY_UNKNOWN;

    uint actual_callee = callee_token_for_hir_call(actual_call_node);
    uint actual_fn = find_function_decl_by_name_id(actual_callee);
    if (!valid_token(actual_fn))
        return TY_UNKNOWN;

    uint return_instance = call_return_type_token[actual_fn];
    if (!same_named_instance_decl(expected_instance, return_instance))
        return TY_UNKNOWN;

    uint arg_tag;
    uint arg_payload;
    if (!instance_arg_ref(return_instance, instance_arg_ordinal, arg_tag, arg_payload))
        return TY_UNKNOWN;

    if (arg_tag == TYPE_REF_GENERIC_PARAM)
        return TY_UNKNOWN;
    return leaf_type_code_for_ref(arg_tag, arg_payload);
}

[noinline]
uint actual_instance_or_call_return_arg_type(
    uint call_node,
    uint ordinal,
    uint expected_instance,
    uint instance_arg_ordinal)
{
    uint actual_ty = actual_instance_arg_type(
        call_node,
        ordinal,
        expected_instance,
        instance_arg_ordinal);
    if (actual_ty != TY_UNKNOWN)
        return actual_ty;
    return actual_call_return_instance_arg_type(
        call_node,
        ordinal,
        expected_instance,
        instance_arg_ordinal);
}

[noinline]
uint actual_instance_or_call_return_arg_type_no_nested_generic_inference(
    uint call_node,
    uint ordinal,
    uint expected_instance,
    uint instance_arg_ordinal)
{
    uint actual_ty = actual_instance_arg_type(
        call_node,
        ordinal,
        expected_instance,
        instance_arg_ordinal);
    if (actual_ty != TY_UNKNOWN)
        return actual_ty;
    return actual_call_return_instance_arg_type_no_nested_generic_inference(
        call_node,
        ordinal,
        expected_instance,
        instance_arg_ordinal);
}

[noinline]
uint actual_type_for_param_generic_slot(
    uint call_node,
    uint fn_i,
    uint ordinal,
    uint slot,
    out bool participates)
{
    participates = false;
    if (ordinal >= PARAM_CACHE_STRIDE || slot == INVALID)
        return TY_UNKNOWN;

    uint param_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        ordinal,
        TY_UNKNOWN);
    if (param_ty == TY_GENERIC_BASE + slot)
    {
        participates = true;
        return arg_expr_type(call_node, ordinal);
    }

    uint expected_instance;
    if (!param_instance_ref(fn_i, ordinal, expected_instance))
        return TY_UNKNOWN;

    uint arg_slot = param_instance_generic_slot(fn_i, ordinal, 0u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type(call_node, ordinal, expected_instance, 0u);
    }
    arg_slot = param_instance_generic_slot(fn_i, ordinal, 1u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type(call_node, ordinal, expected_instance, 1u);
    }
    arg_slot = param_instance_generic_slot(fn_i, ordinal, 2u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type(call_node, ordinal, expected_instance, 2u);
    }
    arg_slot = param_instance_generic_slot(fn_i, ordinal, 3u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type(call_node, ordinal, expected_instance, 3u);
    }

    return TY_UNKNOWN;
}

[noinline]
uint actual_type_for_param_generic_slot_no_nested_call(
    uint call_node,
    uint fn_i,
    uint ordinal,
    uint slot,
    out bool participates)
{
    participates = false;
    if (ordinal >= PARAM_CACHE_STRIDE || slot == INVALID)
        return TY_UNKNOWN;

    uint param_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        ordinal,
        TY_UNKNOWN);
    if (param_ty == TY_GENERIC_BASE + slot)
    {
        participates = true;
        return arg_expr_type_no_nested_call(call_node, ordinal);
    }

    uint expected_instance;
    if (!param_instance_ref(fn_i, ordinal, expected_instance))
        return TY_UNKNOWN;

    uint arg_slot = param_instance_generic_slot(fn_i, ordinal, 0u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type_no_nested_generic_inference(
            call_node,
            ordinal,
            expected_instance,
            0u);
    }
    arg_slot = param_instance_generic_slot(fn_i, ordinal, 1u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type_no_nested_generic_inference(
            call_node,
            ordinal,
            expected_instance,
            1u);
    }
    arg_slot = param_instance_generic_slot(fn_i, ordinal, 2u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type_no_nested_generic_inference(
            call_node,
            ordinal,
            expected_instance,
            2u);
    }
    arg_slot = param_instance_generic_slot(fn_i, ordinal, 3u);
    if (arg_slot == slot)
    {
        participates = true;
        return actual_instance_or_call_return_arg_type_no_nested_generic_inference(
            call_node,
            ordinal,
            expected_instance,
            3u);
    }

    return TY_UNKNOWN;
}

[noinline]
bool generic_slot_consistent_with_prior(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_i,
    uint prev_i,
    uint slot,
    uint arg_ty)
{
    if (prev_i >= arg_i)
        return true;

    bool participates;
    uint prev_ty = actual_type_for_param_generic_slot(
        call_node,
        fn_i,
        prev_i,
        slot,
        participates);
    if (!participates || prev_ty == TY_UNKNOWN || arg_ty == TY_UNKNOWN)
        return true;

    if (prev_ty != arg_ty)
    {
        uint arg_node = call_arg_node_for_call(call_node, arg_i);
        uint arg_token = valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
        record_error(arg_token, ERR_ASSIGN_MISMATCH, (TY_GENERIC_BASE + slot) * 256u + arg_ty);
        return false;
    }
    return true;
}

[noinline]
bool check_argument_cache_bounds(uint callee_i, uint fn_i)
{
    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (param_count == arg_count)
        return true;

    record_error(callee_i, ERR_CALL_MISMATCH, param_count * 256u + arg_count);
    return false;
}

[noinline]
bool merge_inferred_generic_arg(
    uint call_node,
    uint fn_i,
    uint ret_ty,
    uint arg_i,
    uint arg_count,
    inout uint inferred)
{
    if (arg_i >= arg_count)
        return true;

    uint ret_slot = ret_ty >= TY_GENERIC_BASE ? ret_ty - TY_GENERIC_BASE : INVALID;
    uint param_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        arg_i,
        TY_UNKNOWN);
    if (param_ty != ret_ty)
    {
        bool participates;
        uint instance_arg_ty = actual_type_for_param_generic_slot_no_nested_call(
            call_node,
            fn_i,
            arg_i,
            ret_slot,
            participates);
        if (!participates)
            return true;
        if (instance_arg_ty == TY_UNKNOWN)
            return false;
        if (inferred == TY_UNKNOWN)
        {
            inferred = instance_arg_ty;
            return true;
        }
        return inferred == instance_arg_ty;
    }

    uint arg_ty = arg_expr_type_no_nested_call(call_node, arg_i);
    if (arg_ty == TY_UNKNOWN)
        return false;
    if (inferred == TY_UNKNOWN)
    {
        inferred = arg_ty;
        return true;
    }
    return inferred == arg_ty;
}

[noinline]
uint inferred_generic_return_type_from_args(
    uint callee_i,
    uint fn_i,
    uint ret_ty)
{
    uint call_node = call_node_for_callee_token(callee_i);
    if (!valid_node(call_node))
        return TY_UNKNOWN;

    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (param_count > PARAM_CACHE_STRIDE ||
        arg_count > PARAM_CACHE_STRIDE ||
        arg_count != param_count)
        return TY_UNKNOWN;

    uint inferred = TY_UNKNOWN;
    if (!merge_inferred_generic_arg(call_node, fn_i, ret_ty, 0u, arg_count, inferred))
        return TY_UNKNOWN;
    if (!merge_inferred_generic_arg(call_node, fn_i, ret_ty, 1u, arg_count, inferred))
        return TY_UNKNOWN;
    if (!merge_inferred_generic_arg(call_node, fn_i, ret_ty, 2u, arg_count, inferred))
        return TY_UNKNOWN;
    if (!merge_inferred_generic_arg(call_node, fn_i, ret_ty, 3u, arg_count, inferred))
        return TY_UNKNOWN;

    return inferred;
}

[noinline]
bool merge_inferred_generic_arg_nested(
    uint call_node,
    uint fn_i,
    uint ret_ty,
    uint arg_i,
    uint arg_count,
    inout uint inferred)
{
    if (arg_i >= arg_count)
        return true;

    uint ret_slot = ret_ty >= TY_GENERIC_BASE ? ret_ty - TY_GENERIC_BASE : INVALID;
    uint param_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        arg_i,
        TY_UNKNOWN);
    if (param_ty != ret_ty)
    {
        bool participates;
        uint instance_arg_ty = actual_type_for_param_generic_slot(
            call_node,
            fn_i,
            arg_i,
            ret_slot,
            participates);
        if (!participates)
            return true;
        if (instance_arg_ty == TY_UNKNOWN)
            return false;
        if (inferred == TY_UNKNOWN)
        {
            inferred = instance_arg_ty;
            return true;
        }
        return inferred == instance_arg_ty;
    }

    uint arg_ty = arg_expr_type(call_node, arg_i);
    if (arg_ty == TY_UNKNOWN)
        return false;
    if (inferred == TY_UNKNOWN)
    {
        inferred = arg_ty;
        return true;
    }
    return inferred == arg_ty;
}

[noinline]
uint inferred_generic_return_type_nested_from_args(
    uint callee_i,
    uint fn_i,
    uint ret_ty)
{
    uint call_node = call_node_for_callee_token(callee_i);
    if (!valid_node(call_node))
        return TY_UNKNOWN;

    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (param_count > PARAM_CACHE_STRIDE ||
        arg_count > PARAM_CACHE_STRIDE ||
        arg_count != param_count)
        return TY_UNKNOWN;

    uint inferred = TY_UNKNOWN;
    if (!merge_inferred_generic_arg_nested(call_node, fn_i, ret_ty, 0u, arg_count, inferred))
        return TY_UNKNOWN;
    if (!merge_inferred_generic_arg_nested(call_node, fn_i, ret_ty, 1u, arg_count, inferred))
        return TY_UNKNOWN;
    if (!merge_inferred_generic_arg_nested(call_node, fn_i, ret_ty, 2u, arg_count, inferred))
        return TY_UNKNOWN;
    if (!merge_inferred_generic_arg_nested(call_node, fn_i, ret_ty, 3u, arg_count, inferred))
        return TY_UNKNOWN;

    return inferred;
}

[noinline]
uint inferred_generic_return_type_direct(uint callee_i, uint fn_i, uint ret_ty)
{
    return inferred_generic_return_type_from_args(callee_i, fn_i, ret_ty);
}

[noinline]
uint direct_call_return_type_direct(uint callee_i)
{
    uint fn_i = find_function_decl_by_name_id(callee_i);
    if (!valid_token(fn_i))
        return TY_UNKNOWN;

    uint ret_ty = call_return_type[fn_i];
    if (!is_generic_type(ret_ty))
        return ret_ty;
    return inferred_generic_return_type_direct(callee_i, fn_i, ret_ty);
}

[noinline]
uint inferred_generic_return_type(uint callee_i, uint fn_i, uint ret_ty)
{
    return inferred_generic_return_type_nested_from_args(callee_i, fn_i, ret_ty);
}

[noinline]
bool generic_arg_consistent_with_prior(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_i,
    uint prev_i,
    uint param_ty,
    uint arg_ty)
{
    if (prev_i >= arg_i)
        return true;

    uint prev_param_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        prev_i,
        TY_UNKNOWN);
    if (prev_param_ty != param_ty)
        return true;

    uint prev_ty = arg_expr_type(call_node, prev_i);
    if (prev_ty != TY_UNKNOWN && prev_ty != arg_ty)
    {
        uint arg_node = call_arg_node_for_call(call_node, arg_i);
        uint arg_token = valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
        record_error(arg_token, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
        return false;
    }
    return true;
}

[noinline]
bool check_generic_argument_consistency_slot(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_count,
    uint arg_i)
{
    if (arg_i >= arg_count)
        return true;

    uint param_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        arg_i,
        TY_UNKNOWN);
    if (!is_generic_type(param_ty))
        return true;

    uint arg_ty = arg_expr_type(call_node, arg_i);
    if (arg_ty == TY_UNKNOWN)
        return true;

    if (!generic_arg_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 0u, param_ty, arg_ty))
        return false;
    if (!generic_arg_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 1u, param_ty, arg_ty))
        return false;
    if (!generic_arg_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 2u, param_ty, arg_ty))
        return false;
    if (!generic_arg_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 3u, param_ty, arg_ty))
        return false;

    uint slot = param_ty - TY_GENERIC_BASE;
    if (!generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 0u, slot, arg_ty))
        return false;
    if (!generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 1u, slot, arg_ty))
        return false;
    if (!generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 2u, slot, arg_ty))
        return false;
    return generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 3u, slot, arg_ty);
}

[noinline]
bool check_generic_instance_argument_consistency_slot_arg(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_i,
    uint instance_arg_i)
{
    uint slot = param_instance_generic_slot(fn_i, arg_i, instance_arg_i);
    if (slot == INVALID)
        return true;

    bool participates;
    uint arg_ty = actual_type_for_param_generic_slot(
        call_node,
        fn_i,
        arg_i,
        slot,
        participates);
    if (!participates)
        return true;
    if (arg_ty == TY_UNKNOWN)
    {
        uint arg_node = call_arg_node_for_call(call_node, arg_i);
        uint arg_token = valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
        record_error(arg_token, ERR_ASSIGN_MISMATCH, (TY_GENERIC_BASE + slot) * 256u + TY_UNKNOWN);
        return false;
    }

    if (!generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 0u, slot, arg_ty))
        return false;
    if (!generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 1u, slot, arg_ty))
        return false;
    if (!generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 2u, slot, arg_ty))
        return false;
    return generic_slot_consistent_with_prior(callee_i, fn_i, call_node, arg_i, 3u, slot, arg_ty);
}

[noinline]
bool check_repeated_instance_generic_slot_pair(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_i,
    uint left_i,
    uint right_i)
{
    uint left_slot = param_instance_generic_slot(fn_i, arg_i, left_i);
    if (left_slot == INVALID)
        return true;

    uint right_slot = param_instance_generic_slot(fn_i, arg_i, right_i);
    if (right_slot == INVALID || right_slot != left_slot)
        return true;

    uint expected_instance;
    if (!param_instance_ref(fn_i, arg_i, expected_instance))
        return true;

    uint left_ty = actual_instance_or_call_return_arg_type(
        call_node,
        arg_i,
        expected_instance,
        left_i);
    uint right_ty = actual_instance_or_call_return_arg_type(
        call_node,
        arg_i,
        expected_instance,
        right_i);
    if (left_ty != TY_UNKNOWN && right_ty != TY_UNKNOWN && left_ty == right_ty)
        return true;

    uint arg_node = call_arg_node_for_call(call_node, arg_i);
    uint arg_token = valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
    uint detail_ty = right_ty == TY_UNKNOWN ? TY_UNKNOWN : right_ty;
    record_error(arg_token, ERR_ASSIGN_MISMATCH, (TY_GENERIC_BASE + left_slot) * 256u + detail_ty);
    return false;
}

[noinline]
bool check_repeated_instance_generic_slots(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_i)
{
    if (!check_repeated_instance_generic_slot_pair(callee_i, fn_i, call_node, arg_i, 0u, 1u))
        return false;
    if (!check_repeated_instance_generic_slot_pair(callee_i, fn_i, call_node, arg_i, 0u, 2u))
        return false;
    if (!check_repeated_instance_generic_slot_pair(callee_i, fn_i, call_node, arg_i, 0u, 3u))
        return false;
    if (!check_repeated_instance_generic_slot_pair(callee_i, fn_i, call_node, arg_i, 1u, 2u))
        return false;
    if (!check_repeated_instance_generic_slot_pair(callee_i, fn_i, call_node, arg_i, 1u, 3u))
        return false;
    return check_repeated_instance_generic_slot_pair(callee_i, fn_i, call_node, arg_i, 2u, 3u);
}

[noinline]
bool check_generic_instance_argument_consistency_slot(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_count,
    uint arg_i)
{
    if (arg_i >= arg_count)
        return true;

    if (!check_generic_instance_argument_consistency_slot_arg(callee_i, fn_i, call_node, arg_i, 0u))
        return false;
    if (!check_generic_instance_argument_consistency_slot_arg(callee_i, fn_i, call_node, arg_i, 1u))
        return false;
    if (!check_generic_instance_argument_consistency_slot_arg(callee_i, fn_i, call_node, arg_i, 2u))
        return false;
    if (!check_generic_instance_argument_consistency_slot_arg(callee_i, fn_i, call_node, arg_i, 3u))
        return false;
    return check_repeated_instance_generic_slots(callee_i, fn_i, call_node, arg_i);
}

[noinline]
bool check_generic_argument_consistency(uint callee_i, uint fn_i)
{
    uint call_node = call_node_for_callee_token(callee_i);
    if (!valid_node(call_node))
        return true;

    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (arg_count != param_count)
        return true;

    if (!check_generic_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 0u))
        return false;
    if (!check_generic_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 1u))
        return false;
    if (!check_generic_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 2u))
        return false;
    if (!check_generic_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 3u))
        return false;
    if (!check_generic_instance_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 0u))
        return false;
    if (!check_generic_instance_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 1u))
        return false;
    if (!check_generic_instance_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 2u))
        return false;
    if (!check_generic_instance_argument_consistency_slot(callee_i, fn_i, call_node, arg_count, 3u))
        return false;
    return true;
}

[noinline]
bool generic_slot_inferred_from_arg(
    uint call_node,
    uint fn_i,
    uint arg_count,
    uint arg_i,
    uint slot,
    inout uint inferred)
{
    if (arg_i >= arg_count)
        return true;

    bool participates;
    uint arg_ty = actual_type_for_param_generic_slot(
        call_node,
        fn_i,
        arg_i,
        slot,
        participates);
    if (!participates)
        return true;
    if (arg_ty == TY_UNKNOWN)
        return false;

    inferred = 1u;
    return true;
}

[noinline]
bool check_required_generic_slot(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_count,
    uint generic_count,
    uint slot)
{
    if (slot >= generic_count)
        return true;

    uint inferred = 0u;
    if (!generic_slot_inferred_from_arg(call_node, fn_i, arg_count, 0u, slot, inferred) ||
        !generic_slot_inferred_from_arg(call_node, fn_i, arg_count, 1u, slot, inferred) ||
        !generic_slot_inferred_from_arg(call_node, fn_i, arg_count, 2u, slot, inferred) ||
        !generic_slot_inferred_from_arg(call_node, fn_i, arg_count, 3u, slot, inferred) ||
        inferred == 0u)
    {
        record_error(
            callee_i,
            ERR_ASSIGN_MISMATCH,
            (TY_GENERIC_BASE + slot) * 256u + TY_UNKNOWN);
        return false;
    }

    return true;
}

[noinline]
bool check_all_generic_parameters_inferred(uint callee_i, uint fn_i)
{
    uint generic_count = valid_token(fn_i) ? type_decl_generic_param_count[fn_i] : 0u;
    if (generic_count == 0u)
        return true;

    if (generic_count > PARAM_CACHE_STRIDE)
    {
        record_error(
            callee_i,
            ERR_ASSIGN_MISMATCH,
            (TY_GENERIC_BASE + PARAM_CACHE_STRIDE) * 256u + TY_UNKNOWN);
        return false;
    }

    uint call_node = call_node_for_callee_token(callee_i);
    if (!valid_node(call_node))
        return true;

    uint arg_count = call_arg_count_for_callee(callee_i);
    if (!check_required_generic_slot(callee_i, fn_i, call_node, arg_count, generic_count, 0u))
        return false;
    if (!check_required_generic_slot(callee_i, fn_i, call_node, arg_count, generic_count, 1u))
        return false;
    if (!check_required_generic_slot(callee_i, fn_i, call_node, arg_count, generic_count, 2u))
        return false;
    return check_required_generic_slot(callee_i, fn_i, call_node, arg_count, generic_count, 3u);
}

[noinline]
bool check_concrete_argument_type_slot(
    uint callee_i,
    uint fn_i,
    uint call_node,
    uint arg_count,
    uint arg_i)
{
    if (arg_i >= arg_count)
        return true;

    uint param_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        arg_i,
        TY_UNKNOWN);
    if (param_ty == TY_UNKNOWN ||
        is_generic_type(param_ty) ||
        is_symbolic_array_type(param_ty))
        return true;

    if (!check_concrete_instance_argument(callee_i, fn_i, call_node, arg_i, param_ty))
        return false;

    uint expected_instance;
    if (param_instance_ref(fn_i, arg_i, expected_instance) &&
        !concrete_leaf_instance_supported(expected_instance))
        return true;

    uint arg_ty = arg_expr_type(call_node, arg_i);
    if (arg_ty == TY_UNKNOWN || arg_ty == param_ty)
        return true;

    uint arg_node = call_arg_node_for_call(call_node, arg_i);
    uint arg_token = valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
    record_error(arg_token, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
    return false;
}

[noinline]
bool check_concrete_argument_types(uint callee_i, uint fn_i)
{
    uint call_node = call_node_for_callee_token(callee_i);
    if (!valid_node(call_node))
        return true;

    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (arg_count != param_count)
        return true;

    if (!check_concrete_argument_type_slot(callee_i, fn_i, call_node, arg_count, 0u))
        return false;
    if (!check_concrete_argument_type_slot(callee_i, fn_i, call_node, arg_count, 1u))
        return false;
    if (!check_concrete_argument_type_slot(callee_i, fn_i, call_node, arg_count, 2u))
        return false;
    if (!check_concrete_argument_type_slot(callee_i, fn_i, call_node, arg_count, 3u))
        return false;
    return true;
}

[noinline]
void resolve_callee_token(uint callee_i, uint call_node)
{
    if (!valid_token(callee_i))
        return;

    if (valid_token(call_fn_index[callee_i]))
        return;

    if (method_call_name_id[callee_i] != INVALID)
        return;

    if (call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint path_i = path_id_for_call(call_node);
    uint fn_i = INVALID;
    if (path_is_qualified(path_i) && path_owner_module_id[path_i] != INVALID)
    {
        fn_i = resolved_function_for_call_path(call_node);
        if (!valid_token(fn_i))
        {
            call_return_type[callee_i] = TY_UNKNOWN;
            return;
        }
    }
    else
    {
        uint key = name_id_by_token[callee_i];
        if (key == INVALID)
        {
            call_return_type[callee_i] = TY_UNKNOWN;
            return;
        }
        uint slot = direct_function_lookup_slot(key);
        if (slot == INVALID)
        {
            fn_i = fallback_function_decl_by_name_id(key);
            if (!valid_token(fn_i))
            {
                call_return_type[callee_i] = TY_UNKNOWN;
                return;
            }
        }
        else
        {
            fn_i = function_lookup_fn[slot];
            if (!valid_token(fn_i) || function_lookup_key[slot] != key)
                fn_i = fallback_function_decl_by_name_id(key);
            if (!valid_token(fn_i))
            {
                call_return_type[callee_i] = TY_UNKNOWN;
                return;
            }
        }
    }

    call_fn_index[callee_i] = fn_i;
    uint ret_ty = call_return_type[fn_i];
    if (!check_argument_cache_bounds(callee_i, fn_i))
        return;
    if (!check_concrete_argument_types(callee_i, fn_i))
        return;
    if (!check_generic_argument_consistency(callee_i, fn_i))
        return;
    if (!check_all_generic_parameters_inferred(callee_i, fn_i))
        return;
    if (is_generic_type(ret_ty))
    {
        uint inferred = inferred_generic_return_type(callee_i, fn_i, ret_ty);
        if (inferred == TY_UNKNOWN)
        {
            record_error(callee_i, ERR_ASSIGN_MISMATCH, ret_ty * 256u + TY_UNKNOWN);
            return;
        }
        ret_ty = inferred;
    }
    call_return_type[callee_i] = ret_ty;
    call_return_type_token[callee_i] = call_return_type_token[fn_i];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (!valid_node(i) || hir_kind[i] != HIR_CALL_EXPR)
        return;
    if (call_record_is_member_call(i) || call_record_is_qualified_path_call(i))
        return;

    uint callee_token = callee_token_for_hir_call(i);
    if (valid_token(callee_token) && method_call_name_id[callee_token] != INVALID)
        return;
    resolve_callee_token(callee_token, i);
}
