// Resolve direct function calls and bounded scalar generic return types.
//
// This pass consumes parser-owned HIR call/argument/expression records plus
// visible declaration/type records. It must run after `type_check_scope_hir`
// publishes visible_type for declarations and uses. It does not inspect token
// kinds, token neighborhoods, source bytes, helper names, or function bodies.

import generated_parse_production_ids;
import gpu_index;
import hir_records;
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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
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
StructuredBuffer<uint> function_lookup_key;
StructuredBuffer<uint> function_lookup_fn;

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

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

bool is_symbolic_array_type(uint ty)
{
    return ty == TY_ARRAY_BASE + TY_UNKNOWN ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint expr_record_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

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

uint call_node_for_callee_token(uint callee_i)
{
    if (!valid_token(callee_i))
        return INVALID;
    return call_arg_record[callee_i].z;
}

bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = hir_call_callee_node[call_node];
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR;
}

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

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;

    uint callee_token = hir_token_pos[callee_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

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

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;
    return call_arg_node[call_node * PARAM_CACHE_STRIDE + ordinal];
}

uint find_function_decl_by_name_id(uint name_i)
{
    if (!valid_token(name_i))
        return INVALID;

    uint cap = lookup_capacity();
    uint key = name_id_by_token[name_i];
    if (key == INVALID)
        return INVALID;
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint fn_i = function_lookup_fn[slot];
        if (fn_i == INVALID)
            return INVALID;
        if (function_lookup_key[slot] == key)
            return fn_i;
    }
    return INVALID;
}

uint direct_call_return_type_direct(uint callee_i);

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
        return valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

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

uint arg_expr_type_no_nested_call(uint call_node, uint ordinal)
{
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    return expr_type_no_nested_call(arg_node);
}

uint arg_expr_type(uint call_node, uint ordinal)
{
    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    return expr_type(arg_node);
}

bool check_argument_cache_bounds(uint callee_i, uint fn_i)
{
    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (param_count <= PARAM_CACHE_STRIDE &&
        arg_count <= PARAM_CACHE_STRIDE &&
        param_count == arg_count)
        return true;

    record_error(callee_i, ERR_CALL_MISMATCH, param_count * 256u + arg_count);
    return false;
}

uint inferred_generic_return_type_direct(uint callee_i, uint fn_i, uint ret_ty)
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
    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = row_major_load<uint>(
            call_param_type,
            fn_i,
            PARAM_CACHE_STRIDE,
            arg_i,
            TY_UNKNOWN);
        if (param_ty != ret_ty)
            continue;

        uint arg_ty = arg_expr_type_no_nested_call(call_node, arg_i);
        if (arg_ty == TY_UNKNOWN)
            return TY_UNKNOWN;
        if (inferred == TY_UNKNOWN)
            inferred = arg_ty;
        else if (inferred != arg_ty)
            return TY_UNKNOWN;
    }

    return inferred;
}

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

uint inferred_generic_return_type(uint callee_i, uint fn_i, uint ret_ty)
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
    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = row_major_load<uint>(
            call_param_type,
            fn_i,
            PARAM_CACHE_STRIDE,
            arg_i,
            TY_UNKNOWN);
        if (param_ty != ret_ty)
            continue;

        uint arg_ty = arg_expr_type(call_node, arg_i);
        if (arg_ty == TY_UNKNOWN)
            return TY_UNKNOWN;
        if (inferred == TY_UNKNOWN)
            inferred = arg_ty;
        else if (inferred != arg_ty)
            return TY_UNKNOWN;
    }

    return inferred;
}

bool check_generic_argument_consistency(uint callee_i, uint fn_i)
{
    uint call_node = call_node_for_callee_token(callee_i);
    if (!valid_node(call_node))
        return true;

    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (arg_count != param_count)
        return true;

    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = row_major_load<uint>(
            call_param_type,
            fn_i,
            PARAM_CACHE_STRIDE,
            arg_i,
            TY_UNKNOWN);
        if (!is_generic_type(param_ty))
            continue;

        uint arg_ty = arg_expr_type(call_node, arg_i);
        if (arg_ty == TY_UNKNOWN)
            continue;

        [loop]
        for (uint prev_i = 0u; prev_i < arg_i && prev_i < PARAM_CACHE_STRIDE; prev_i += 1u)
        {
            uint prev_param_ty = row_major_load<uint>(
                call_param_type,
                fn_i,
                PARAM_CACHE_STRIDE,
                prev_i,
                TY_UNKNOWN);
            if (prev_param_ty != param_ty)
                continue;

            uint prev_ty = arg_expr_type(call_node, prev_i);
            if (prev_ty != TY_UNKNOWN && prev_ty != arg_ty)
            {
                uint arg_node = call_arg_node_for_call(call_node, arg_i);
                uint arg_token = valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
                record_error(arg_token, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
                return false;
            }
        }
    }
    return true;
}

bool check_concrete_argument_types(uint callee_i, uint fn_i)
{
    uint call_node = call_node_for_callee_token(callee_i);
    if (!valid_node(call_node))
        return true;

    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (arg_count != param_count)
        return true;

    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = row_major_load<uint>(
            call_param_type,
            fn_i,
            PARAM_CACHE_STRIDE,
            arg_i,
            TY_UNKNOWN);
        if (param_ty == TY_UNKNOWN ||
            is_generic_type(param_ty) ||
            is_symbolic_array_type(param_ty))
            continue;

        uint arg_ty = arg_expr_type(call_node, arg_i);
        if (arg_ty == TY_UNKNOWN || arg_ty == param_ty)
            continue;

        uint arg_node = call_arg_node_for_call(call_node, arg_i);
        uint arg_token = valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
        record_error(arg_token, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
        return false;
    }

    return true;
}

void resolve_callee_token(uint callee_i)
{
    if (!valid_token(callee_i))
        return;

    if (call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint cap = lookup_capacity();
    uint key = name_id_by_token[callee_i];
    if (key == INVALID)
    {
        call_return_type[callee_i] = TY_UNKNOWN;
        return;
    }
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint fn_i = function_lookup_fn[slot];
        if (fn_i == INVALID)
            return;
        if (function_lookup_key[slot] == key)
        {
            call_fn_index[callee_i] = fn_i;
            uint ret_ty = call_return_type[fn_i];
            if (!check_argument_cache_bounds(callee_i, fn_i))
                return;
            if (!check_concrete_argument_types(callee_i, fn_i))
                return;
            if (!check_generic_argument_consistency(callee_i, fn_i))
                return;
            if (is_generic_type(ret_ty))
            {
                uint inferred = inferred_generic_return_type(callee_i, fn_i, ret_ty);
                if (inferred != TY_UNKNOWN)
                    ret_ty = inferred;
            }
            call_return_type[callee_i] = ret_ty;
            call_return_type_token[callee_i] = call_return_type_token[fn_i];
            return;
        }
    }

    call_return_type[callee_i] = TY_UNKNOWN;
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
    resolve_callee_token(callee_token);
}
