// Scatter file/std/string host-call WASM body fragments.

import gpu_index;
import prefix_scan;
import call_relocation;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<ScanParams> gScan;
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_call_arg_count;
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
StructuredBuffer<uint> wasm_func_local_max_by_token;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LET_HOST_CALL_I32 = 37u;
static const uint BODY_FRAGMENT_LET_HOST_STR_CALL_I32 = 39u;
static const uint BODY_FRAGMENT_RETURN_HOST_CALL_I32 = 47u;
static const uint BODY_FRAGMENT_RETURN_HOST_STR_CALL_I32 = 48u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
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
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_CALL_EXPR = 19u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_RETURN = 0x0fu;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I32_EQ = 0x46u;
static const uint WASM_I32_NE = 0x47u;
static const uint WASM_I32_LT_S = 0x48u;
static const uint WASM_I32_GT_S = 0x4au;
static const uint WASM_I32_LE_S = 0x4cu;
static const uint WASM_I32_GE_S = 0x4eu;
static const uint WASM_I32_ADD = 0x6au;
static const uint WASM_I32_SUB = 0x6bu;
static const uint WASM_I32_MUL = 0x6cu;
static const uint WASM_I32_DIV_S = 0x6du;
static const uint WASM_I32_REM_S = 0x6fu;
static const uint WASM_I32_AND = 0x71u;
static const uint WASM_I32_OR = 0x72u;
static const uint WASM_I32_XOR = 0x73u;
static const uint WASM_I32_SHL = 0x74u;
static const uint WASM_I32_SHR_S = 0x75u;
static const uint WASM_F32_NEG = 0x8cu;
static const uint WASM_F32_ADD = 0x92u;
static const uint WASM_F32_SUB = 0x93u;
static const uint WASM_F32_MUL = 0x94u;
static const uint WASM_F32_DIV = 0x95u;
static const uint HOST_STR_CALL_OPEN_READ_PATH = 1u;
static const uint HOST_STR_CALL_OPEN_WRITE_PATH = 2u;
static const uint HOST_STR_CALL_WRITE_TEXT = 3u;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(token_i, WG_SIZE, body_scan_local_prefix, body_scan_block_prefix);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
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

uint u32_leb_byte(uint value, uint byte_i)
{
    uint shift = byte_i * 7u;
    uint byte_value = (value >> shift) & 0x7fu;
    return (value >> (shift + 7u)) == 0u ? byte_value : (byte_value | 0x80u);
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

uint i32_sleb_byte(uint value, uint byte_i)
{
    int v = int(value);
    for (uint i = 0u; i < byte_i; i += 1u)
        v = v >> 7;
    uint byte_value = uint(v) & 0x7fu;
    int next = v >> 7;
    bool sign = (byte_value & 0x40u) != 0u;
    bool done = (next == 0 && !sign) || (next == -1 && sign);
    return done ? byte_value : (byte_value | 0x80u);
}

uint i32_const_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;
    return i32_sleb_byte(value, byte_i - 1u);
}

uint f32_const_byte(uint bits, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_F32_CONST;
    return (bits >> ((byte_i - 1u) * 8u)) & 0xffu;
}

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_set_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
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

uint function_param_abi_count(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;
    uint count = call_param_count[fn_token];
    uint total = 0u;
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
        total += call_param_type_value(fn_token, ordinal) == TY_STRING ? 2u : 1u;
    return total;
}

bool function_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    uint param_count = call_param_count[fn_token];
    if (ordinal == INVALID || ordinal >= param_count)
        return false;
    local_index = 0u;
    for (uint i = 0u; i < ordinal; i += 1u)
        local_index += call_param_type_value(fn_token, i) == TY_STRING ? 2u : 1u;
    return true;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint local_count = 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    if (local_max != INVALID)
        local_count = local_max + 1u;
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
        uint ptr_index = 0u;
        for (uint i = 0u; i < ordinal; i += 1u)
            ptr_index += call_param_type_value(fn_token, i) == TY_STRING ? 2u : 1u;
        local_index = ptr_index + 1u;
        return true;
    }
    if (visible_type_for_token(decl_token) != TY_STRING)
        return false;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    uint local_count = local_max == INVALID ? 0u : local_max + 1u;
    local_index = function_param_abi_count(fn_token) + local_count + decl_token;
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

uint string_value_expr_len(uint node)
{
    uint ptr = 0u;
    uint str_len = 0u;
    if (string_literal_ptr_len(node, ptr, str_len))
        return 1u + i32_sleb_len(ptr) + 1u + i32_sleb_len(str_len);
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return 0u;
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
        return 0u;
    }
    return local_get_len(ptr_local) + local_get_len(len_local);
}

uint string_value_expr_byte(uint node, uint byte_i)
{
    uint ptr = 0u;
    uint str_len = 0u;
    if (string_literal_ptr_len(node, ptr, str_len))
    {
        uint ptr_len = 1u + i32_sleb_len(ptr);
        if (byte_i < ptr_len)
            return i32_const_byte(ptr, byte_i);
        return i32_const_byte(str_len, byte_i - ptr_len);
    }
    node = resolve_expr_node(node);
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint ptr_local = INVALID;
    uint len_local = INVALID;
    if (!local_index_for_name_expr(node, ptr_local) ||
        !function_string_len_local_index(decl_token, owner_fn, len_local))
    {
        return 0u;
    }
    uint ptr_len = local_get_len(ptr_local);
    if (byte_i < ptr_len)
        return local_get_byte(ptr_local, byte_i);
    return local_get_byte(len_local, byte_i - ptr_len);
}

uint i32_binary_op_byte(uint form)
{
    if (form == HIR_EXPR_EQ) return WASM_I32_EQ;
    if (form == HIR_EXPR_NE) return WASM_I32_NE;
    if (form == HIR_EXPR_LT) return WASM_I32_LT_S;
    if (form == HIR_EXPR_GT) return WASM_I32_GT_S;
    if (form == HIR_EXPR_LE) return WASM_I32_LE_S;
    if (form == HIR_EXPR_GE) return WASM_I32_GE_S;
    if (form == HIR_EXPR_ADD) return WASM_I32_ADD;
    if (form == HIR_EXPR_SUB) return WASM_I32_SUB;
    if (form == HIR_EXPR_MUL) return WASM_I32_MUL;
    if (form == HIR_EXPR_DIV) return WASM_I32_DIV_S;
    if (form == HIR_EXPR_MOD) return WASM_I32_REM_S;
    if (form == HIR_EXPR_AND || form == HIR_EXPR_BIT_AND) return WASM_I32_AND;
    if (form == HIR_EXPR_OR || form == HIR_EXPR_BIT_OR) return WASM_I32_OR;
    if (form == HIR_EXPR_BIT_XOR) return WASM_I32_XOR;
    if (form == HIR_EXPR_SHL) return WASM_I32_SHL;
    if (form == HIR_EXPR_SHR) return WASM_I32_SHR_S;
    return 0u;
}

uint f32_binary_op_byte(uint form)
{
    if (form == HIR_EXPR_ADD) return WASM_F32_ADD;
    if (form == HIR_EXPR_SUB) return WASM_F32_SUB;
    if (form == HIR_EXPR_MUL) return WASM_F32_MUL;
    if (form == HIR_EXPR_DIV) return WASM_F32_DIV;
    return 0u;
}

bool expr_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    return valid_node(node) && expr_form(node) == HIR_EXPR_FLOAT;
}

uint expr_op_byte(uint node)
{
    uint form = expr_form(node);
    bool f32_op = expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ||
                  expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_RIGHT));
    return f32_op ? f32_binary_op_byte(form) : i32_binary_op_byte(form);
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

uint expr_atom_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint form = expr_form(node);
    uint local_index = INVALID;
    uint const_value = 0u;
    if (form == HIR_EXPR_NAME && local_index_for_name_expr(node, local_index))
        return local_get_byte(local_index, byte_i);
    if (form == HIR_EXPR_NAME && name_const_record_value(node, const_value))
        return i32_const_byte(const_value, byte_i);
    if (form == HIR_EXPR_INT)
        return i32_const_byte(hir_expr_int_value[node], byte_i);
    if (form == HIR_EXPR_FLOAT)
        return f32_const_byte(hir_expr_float_bits[node], byte_i);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
    return 0u;
}

bool const_atom_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return form == HIR_EXPR_NAME && name_const_record_value(node, value);
}

bool unary_const_value(uint form, uint inner, out uint value)
{
    value = 0u;
    if (form == HIR_EXPR_NEG)
    {
        value = uint(-int(inner));
        return true;
    }
    if (form == HIR_EXPR_NOT)
    {
        value = inner == 0u ? 1u : 0u;
        return true;
    }
    return false;
}

bool direct_call_arg_const_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    if (const_atom_value(node, value))
        return true;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint inner = 0u;
        if (!const_atom_value(expr_record_slot(node, EXPR_RECORD_LEFT), inner) &&
            !const_atom_value(expr_record_slot(node, EXPR_RECORD_RIGHT), inner))
        {
            return false;
        }
        return unary_const_value(form, inner, value);
    }
    return false;
}

uint direct_call_arg_scalar_len(uint node)
{
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return atom_len;

    uint value = 0u;
    return direct_call_arg_const_value(node, value) ? 1u + i32_sleb_len(value) : 0u;
}

uint direct_call_arg_scalar_byte(uint node, uint byte_i)
{
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return expr_atom_byte(node, byte_i);

    uint value = 0u;
    if (direct_call_arg_const_value(node, value))
        return i32_const_byte(value, byte_i);
    return 0u;
}

uint expr_len(uint node)
{
    node = resolve_expr_node(node);
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return atom_len;
    uint form = expr_form(node);
    uint left_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
    if (form == HIR_EXPR_NOT)
        return left_len == 0u ? 0u : left_len + 1u;
    if (form == HIR_EXPR_NEG)
        return left_len == 0u ? 0u : left_len + (expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ? 1u : 3u);
    uint right_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT));
    uint op = expr_op_byte(node);
    return op == 0u || left_len == 0u || right_len == 0u ? 0u : left_len + right_len + 1u;
}

uint expr_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return expr_atom_byte(node, byte_i);
    uint form = expr_form(node);
    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint left_len = expr_atom_len(left);
    if (form == HIR_EXPR_NOT)
    {
        if (byte_i < left_len)
            return expr_atom_byte(left, byte_i);
        return WASM_I32_EQZ;
    }
    if (form == HIR_EXPR_NEG)
    {
        if (expr_atom_is_f32(left))
        {
            if (byte_i < left_len)
                return expr_atom_byte(left, byte_i);
            return WASM_F32_NEG;
        }
        if (byte_i < 2u)
            return i32_const_byte(0u, byte_i);
        if (byte_i < 2u + left_len)
            return expr_atom_byte(left, byte_i - 2u);
        return WASM_I32_SUB;
    }
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint right_len = expr_atom_len(right);
    if (byte_i < left_len)
        return expr_atom_byte(left, byte_i);
    if (byte_i < left_len + right_len)
        return expr_atom_byte(right, byte_i - left_len);
    return expr_op_byte(node);
}

uint direct_call_arg_node(uint call_node, uint ordinal)
{
    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count || ordinal >= hir_call_arg_count[call_node])
        return INVALID;
    uint row = start + ordinal;
    if (row >= gParams.n_hir_nodes)
        return INVALID;
    uint node = call_arg_row_node[row];
    return valid_node(node) ? node : INVALID;
}

uint host_i32_call_byte(uint call_node, uint wasm_func_index, uint arg_count, uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    uint offset = 0u;
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_arg_node(call_node, i);
        uint arg_len = direct_call_arg_scalar_len(arg_node);
        if (byte_i < offset + arg_len)
            return direct_call_arg_scalar_byte(arg_node, byte_i - offset);
        offset += arg_len;
    }
    if (byte_i == offset)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - offset - 1u);
}

uint string_ptr_len_call_byte(uint string_node, uint wasm_func_index, uint byte_i)
{
    uint string_len = string_value_expr_len(string_node);
    if (byte_i < string_len)
        return string_value_expr_byte(string_node, byte_i);
    if (byte_i == string_len)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - string_len - 1u);
}

uint handle_string_call_byte(uint call_node, uint wasm_func_index, uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    uint handle_node = direct_call_arg_node(call_node, 0u);
    uint handle_len = direct_call_arg_scalar_len(handle_node);
    if (byte_i < handle_len)
        return direct_call_arg_scalar_byte(handle_node, byte_i);
    uint string_node = direct_call_arg_node(call_node, 1u);
    uint string_start = handle_len;
    uint string_len = string_value_expr_len(string_node);
    if (byte_i < string_start + string_len)
        return string_value_expr_byte(string_node, byte_i - string_start);
    uint call_start = string_start + string_len;
    if (byte_i == call_start)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - call_start - 1u);
}

uint host_string_call_byte(uint call_node, uint wasm_func_index, uint mode, uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    if (mode == HOST_STR_CALL_OPEN_READ_PATH || mode == HOST_STR_CALL_OPEN_WRITE_PATH)
        return string_ptr_len_call_byte(direct_call_arg_node(call_node, 0u), wasm_func_index, byte_i);
    if (mode == HOST_STR_CALL_WRITE_TEXT)
        return handle_string_call_byte(call_node, wasm_func_index, byte_i);
    return 0u;
}

uint let_host_call_i32_fragment_byte(uint local_index, uint call_node, uint wasm_func_index, uint arg_count, uint fragment_len, uint byte_i)
{
    uint set_len = local_set_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i < call_len)
        return host_i32_call_byte(call_node, wasm_func_index, arg_count, byte_i);
    return local_set_byte(local_index, byte_i - call_len);
}

uint let_host_string_call_i32_fragment_byte(uint local_index, uint call_node, uint wasm_func_index, uint mode, uint fragment_len, uint byte_i)
{
    uint set_len = local_set_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i < call_len)
        return host_string_call_byte(call_node, wasm_func_index, mode, byte_i);
    return local_set_byte(local_index, byte_i - call_len);
}

uint return_host_call_i32_fragment_byte(uint call_node, uint wasm_func_index, uint arg_count, uint fragment_len, uint byte_i)
{
    uint call_len = fragment_len > 0u ? fragment_len - 1u : 0u;
    if (byte_i < call_len)
        return host_i32_call_byte(call_node, wasm_func_index, arg_count, byte_i);
    return WASM_RETURN;
}

uint return_host_string_call_i32_fragment_byte(uint call_node, uint wasm_func_index, uint mode, uint fragment_len, uint byte_i)
{
    uint call_len = fragment_len > 0u ? fragment_len - 1u : 0u;
    if (byte_i < call_len)
        return host_string_call_byte(call_node, wasm_func_index, mode, byte_i);
    return WASM_RETURN;
}

bool scatter_handles_kind(uint kind)
{
    return kind == BODY_FRAGMENT_LET_HOST_STR_CALL_I32 ||
           kind == BODY_FRAGMENT_RETURN_HOST_STR_CALL_I32;
}

uint fragment_byte(uint4 meta, uint4 aux, uint fragment_len, uint byte_i)
{
    if (meta.x == BODY_FRAGMENT_LET_HOST_STR_CALL_I32)
        return let_host_string_call_i32_fragment_byte(meta.y, meta.z, meta.w, aux.y, fragment_len, byte_i);
    if (meta.x == BODY_FRAGMENT_RETURN_HOST_STR_CALL_I32)
        return return_host_string_call_i32_fragment_byte(meta.y, meta.z, aux.z, fragment_len, byte_i);
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u)
        return;

    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_start = body_prefix_for_token(mid);
        uint mid_end = mid_start + body_fragment_len[mid];
        if (mid_end <= body_byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }

    uint token_i = lo;
    if (token_i >= gScan.n_items)
        return;
    uint len = body_fragment_len[token_i];
    uint offset = body_prefix_for_token(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len)
        return;

    uint4 meta = body_fragment_meta[token_i];
    if (!scatter_handles_kind(meta.x))
        return;

    uint byte_i = body_byte_i - offset;
    uint4 aux = body_fragment_aux[token_i];
    body_words[offset + byte_i] = fragment_byte(meta, aux, len, byte_i);
}
