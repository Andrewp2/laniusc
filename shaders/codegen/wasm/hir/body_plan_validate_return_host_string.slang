// Parallel validation and planning for string-backed host-call return values.

import atomics;
import gpu_index;
import call_relocation;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;

static const uint INVALID = 0xffffffffu;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_RETURN_VALUE_OK_COUNT = 20u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_HOST = 1u << 2u;
static const uint BODY_FEATURE_HOST_IO = 1u << 18u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_CALL_EXPR = 19u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint LANGUAGE_SYMBOL_OPEN_READ_PATH = 20u;
static const uint LANGUAGE_SYMBOL_OPEN_WRITE_PATH = 21u;
static const uint LANGUAGE_SYMBOL_WRITE_TEXT = 23u;
static const uint HOST_STR_CALL_OPEN_READ_PATH = 1u;
static const uint HOST_STR_CALL_OPEN_WRITE_PATH = 2u;
static const uint HOST_STR_CALL_WRITE_TEXT = 3u;
static const uint WASM_STD_OPEN_READ_PATH_FUNC_INDEX = 28u;
static const uint WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX = 29u;
static const uint WASM_STD_WRITE_TEXT_FUNC_INDEX = 30u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint BODY_FRAGMENT_RETURN_HOST_STR_CALL_I32 = 48u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(hir_stmt_record, node, STMT_RECORD_STRIDE, slot, INVALID);
}

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(hir_expr_record, node, EXPR_RECORD_STRIDE, slot, INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint resolve_expr_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    if (valid_node(root))
        return root;
    return expr_form(node) == HIR_EXPR_FORWARD ? INVALID : node;
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value = value >> 7u;
        if (value == 0u)
            return i + 1u;
    }
    return 5u;
}

uint i32_sleb_len(uint value)
{
    int v = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        int byte_value = v & 0x7f;
        v = v >> 7;
        bool sign = (byte_value & 0x40) != 0;
        if ((v == 0 && !sign) || (v == -1 && sign))
            return i + 1u;
    }
    return 5u;
}

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = visible_type[token];
    if (ty != INVALID && ty != TY_UNKNOWN)
        return ty;
    uint decl = visible_decl[token];
    if (!valid_token(decl))
        return TY_UNKNOWN;
    ty = visible_type[decl];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token))
        return TY_UNKNOWN;

    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint row_limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start > row_limit || ordinal > row_limit - start)
        return TY_UNKNOWN;

    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return TY_UNKNOWN;
    }

    return call_param_row_type[row];
}

uint wasm_value_abi_width(uint ty)
{
    return ty == TY_STRING ? 2u : 1u;
}

uint function_param_abi_count(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;

    uint count = call_param_count[fn_token];
    uint total = 0u;
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
        total += wasm_value_abi_width(call_param_type_value(fn_token, ordinal));
    return total;
}

uint function_param_abi_ordinal(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal >= call_param_count[fn_token])
        return INVALID;

    uint local_index = 0u;
    for (uint i = 0u; i < ordinal; i += 1u)
        local_index += wasm_value_abi_width(call_param_type_value(fn_token, i));
    return local_index;
}

uint local_decl_count_for_function_token(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    return local_max == INVALID ? 0u : local_max + 1u;
}

bool function_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal == INVALID || ordinal >= call_param_count[fn_token])
        return false;
    local_index = function_param_abi_ordinal(fn_token, ordinal);
    return local_index != INVALID;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint local_count = local_decl_count_for_function_token(fn_token);
    local_index = function_param_abi_count(fn_token) + decl_token;
    if (visible_type_for_token(decl_token) == TY_FLOAT)
        local_index += local_count * 2u;
    return true;
}

bool function_string_len_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal != INVALID && ordinal < call_param_count[fn_token])
    {
        if (call_param_type_value(fn_token, ordinal) != TY_STRING)
            return false;
        uint ptr_index = function_param_abi_ordinal(fn_token, ordinal);
        if (ptr_index == INVALID)
            return false;
        local_index = ptr_index + 1u;
        return true;
    }

    if (visible_type_for_token(decl_token) != TY_STRING)
        return false;
    local_index = function_param_abi_count(fn_token) +
                  local_decl_count_for_function_token(fn_token) +
                  decl_token;
    return true;
}

bool local_index_for_name_expr(uint node, out uint local_index)
{
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    if (function_param_local_index(decl_token, owner_fn, local_index))
        return true;
    if (body_let_init_expr_by_decl_token[decl_token] == INVALID)
        return false;
    return function_non_param_local_index(decl_token, owner_fn, local_index);
}

bool name_const_record_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint2 record = wasm_const_value_record[decl_token];
    if (record.x != WASM_CONST_VALUE_LITERAL)
        return false;
    value = record.y;
    return true;
}

uint expr_atom_len(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;
    uint form = expr_form(node);
    uint local_index = INVALID;
    uint const_value = 0u;
    if (form == HIR_EXPR_NAME && local_index_for_name_expr(node, local_index))
        return local_get_len(local_index);
    if (form == HIR_EXPR_NAME && name_const_record_value(node, const_value))
        return 1u + i32_sleb_len(const_value);
    if (form == HIR_EXPR_INT)
        return 1u + i32_sleb_len(hir_expr_int_value[node]);
    if (form == HIR_EXPR_FLOAT)
        return 5u;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return 2u;
    return 0u;
}

bool direct_call_arg_scalar_and_len(uint node, out uint len)
{
    len = expr_atom_len(node);
    if (len != 0u)
        return true;

    node = resolve_expr_node(node);
    uint form = expr_form(node);
    uint left_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
    if (form == HIR_EXPR_NOT)
    {
        len = left_len == 0u ? 0u : left_len + 1u;
        return len != 0u;
    }
    if (form == HIR_EXPR_NEG)
    {
        len = left_len == 0u ? 0u : left_len + 3u;
        return len != 0u;
    }
    return false;
}

uint source_data_base()
{
    return (gParams.n_tokens + 1u) * 4u;
}

bool string_literal_ptr_len(uint node, out uint ptr, out uint len)
{
    ptr = 0u;
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_STRING)
        return false;

    uint start = hir_expr_string_start[node];
    uint raw_len = hir_expr_string_len[node];
    if (start == INVALID || start > gParams.source_len || raw_len > gParams.source_len - start)
        return false;

    ptr = source_data_base() + start;
    len = raw_len;
    return true;
}

bool string_value_expr_and_len(uint node, out uint len)
{
    len = 0u;
    uint ptr = 0u;
    uint str_len = 0u;
    if (string_literal_ptr_len(node, ptr, str_len))
    {
        len = 1u + i32_sleb_len(ptr) + 1u + i32_sleb_len(str_len);
        return true;
    }

    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint ptr_local = INVALID;
    uint len_local = INVALID;
    if (!valid_token(decl_token) ||
        visible_type_for_token(decl_token) != TY_STRING ||
        !local_index_for_name_expr(node, ptr_local) ||
        !function_string_len_local_index(decl_token, owner_fn, len_local))
    {
        return false;
    }

    len = local_get_len(ptr_local) + local_get_len(len_local);
    return true;
}

uint direct_call_arg_node(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= hir_call_arg_count[call_node])
        return INVALID;

    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    if (row >= gParams.n_hir_nodes)
        return INVALID;

    uint node = call_arg_row_node[row];
    return valid_node(node) ? node : INVALID;
}

uint call_site_token(uint call_node)
{
    return valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = call_site_token(call_node);
    uint callee_node = resolve_expr_node(hir_call_callee_node[call_node]);
    uint callee_token = valid_node(callee_node)
                            ? expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN)
                            : INVALID;
    if (!valid_token(callee_token))
        callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_metadata_token(uint call_node, uint callee_token)
{
    uint site_token = call_site_token(call_node);
    if (valid_token(site_token) && valid_token(call_fn_index[site_token]))
        return site_token;
    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token]))
        return callee_token;
    return callee_token;
}

uint call_fn_token_for_call(uint call_node, uint callee_token)
{
    uint metadata_token = call_metadata_token(call_node, callee_token);
    return valid_token(metadata_token) ? call_fn_index[metadata_token] : INVALID;
}

uint call_return_type_for_call(uint call_node, uint callee_token, uint fn_token)
{
    uint metadata_token = call_metadata_token(call_node, callee_token);
    uint metadata_return_ty = valid_token(metadata_token) ? call_return_type[metadata_token] : TY_UNKNOWN;
    return metadata_return_ty != TY_UNKNOWN && metadata_return_ty != INVALID
               ? metadata_return_ty
               : call_return_type[fn_token];
}

bool token_has_language_name(uint name_token, uint language_symbol)
{
    if (!valid_token(name_token) || language_symbol >= 63u)
        return false;
    uint name_id = name_id_by_token[name_token];
    uint language_id = language_name_id[language_symbol];
    return name_id != INVALID && language_id != INVALID && name_id == language_id;
}

bool host_string_i32_call_node(uint call_node, uint language_symbol, uint expected_arg_count)
{
    call_node = resolve_expr_node(call_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token) ||
        (!token_has_language_name(callee_token, language_symbol) &&
         !token_has_language_name(fn_token, language_symbol)))
    {
        return false;
    }

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    bool return_ok = return_ty == TY_INT || return_ty == TY_UINT;
    return hir_call_arg_count[call_node] == expected_arg_count && return_ok;
}

bool host_string_i32_call_expr_and_len(
    uint call_node,
    uint language_symbol,
    uint wasm_func_index,
    uint mode,
    out uint len)
{
    len = 0u;
    call_node = resolve_expr_node(call_node);

    if (mode == HOST_STR_CALL_OPEN_READ_PATH || mode == HOST_STR_CALL_OPEN_WRITE_PATH)
    {
        if (!host_string_i32_call_node(call_node, language_symbol, 1u))
            return false;
        uint string_len = 0u;
        if (!string_value_expr_and_len(direct_call_arg_node(call_node, 0u), string_len))
            return false;
        len = string_len + 1u + wasm_call_index_len(wasm_func_index);
        return true;
    }

    if (mode == HOST_STR_CALL_WRITE_TEXT)
    {
        if (!host_string_i32_call_node(call_node, language_symbol, 2u))
            return false;
        uint handle_len = 0u;
        uint string_len = 0u;
        if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, 0u), handle_len) ||
            !string_value_expr_and_len(direct_call_arg_node(call_node, 1u), string_len))
        {
            return false;
        }
        len = handle_len + string_len + 1u + wasm_call_index_len(wasm_func_index);
        return true;
    }

    return false;
}

bool supported_return_host_string_fragment(
    uint node,
    out uint call_node,
    out uint wasm_func_index,
    out uint mode,
    out uint len)
{
    call_node = INVALID;
    wasm_func_index = INVALID;
    mode = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_RETURN_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return false;
    }

    call_node = resolve_expr_node(stmt_record_slot(node, 1u));
    if (host_string_i32_call_expr_and_len(
            call_node,
            LANGUAGE_SYMBOL_OPEN_READ_PATH,
            WASM_STD_OPEN_READ_PATH_FUNC_INDEX,
            HOST_STR_CALL_OPEN_READ_PATH,
            len))
    {
        wasm_func_index = WASM_STD_OPEN_READ_PATH_FUNC_INDEX;
        mode = HOST_STR_CALL_OPEN_READ_PATH;
    }
    else if (host_string_i32_call_expr_and_len(
                 call_node,
                 LANGUAGE_SYMBOL_OPEN_WRITE_PATH,
                 WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX,
                 HOST_STR_CALL_OPEN_WRITE_PATH,
                 len))
    {
        wasm_func_index = WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX;
        mode = HOST_STR_CALL_OPEN_WRITE_PATH;
    }
    else if (host_string_i32_call_expr_and_len(
                 call_node,
                 LANGUAGE_SYMBOL_WRITE_TEXT,
                 WASM_STD_WRITE_TEXT_FUNC_INDEX,
                 HOST_STR_CALL_WRITE_TEXT,
                 len))
    {
        wasm_func_index = WASM_STD_WRITE_TEXT_FUNC_INDEX;
        mode = HOST_STR_CALL_WRITE_TEXT;
    }
    else
    {
        return false;
    }

    len += 1u;
    return true;
}

void main_return_host_string(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (!valid_token(token) || body_fragment_len[token * 2u] != 0u)
        return;

    uint expr_node = INVALID;
    uint wasm_func_index = INVALID;
    uint mode = 0u;
    uint len = 0u;
    if (!supported_return_host_string_fragment(node, expr_node, wasm_func_index, mode, len))
        return;

    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
    if (valid_token(owner_fn))
        atomic_u32_add(wasm_func_body_len_by_token, owner_fn, len);
    uint slot = token * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = uint4(BODY_FRAGMENT_RETURN_HOST_STR_CALL_I32, expr_node, wasm_func_index, token);
    body_fragment_aux[slot] = uint4(INVALID, 0u, mode, 0u);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_HOST | BODY_FEATURE_HOST_IO);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != 1u)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node) || hir_kind[node] != HIR_RETURN_STMT)
        return;
    main_return_host_string(node, hir_token_pos[node]);
}
