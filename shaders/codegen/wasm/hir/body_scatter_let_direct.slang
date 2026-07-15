// Scatter scalar WASM let-direct-call fragments from HIR argument rows.

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
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 = 23u;
static const uint BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 = 24u;
static const uint BODY_FRAGMENT_LET_DIRECT_CALL_I32 = 25u;
static const uint BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 = 26u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 = 27u;
static const uint BODY_FRAGMENT_DIRECT_CALL_VOID = 59u;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
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
static const uint HIR_MEMBER_EXPR = 21u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_RETURN = 0x0fu;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I64_EXTEND_I32_S = 0xacu;
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
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
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

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
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

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal != 0u)
        return false;
    uint mode = method_decl_receiver_mode[fn_token];
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token))
        return TY_UNKNOWN;

    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint row_limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start > row_limit || ordinal > row_limit - start)
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;

    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;
    }

    uint ty = call_param_row_type[row];
    return ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal)
               ? TY_ARRAY_BASE
               : ty;
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
    if (!valid_token(fn_token))
        return INVALID;

    uint count = call_param_count[fn_token];
    if (ordinal >= count)
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
    uint param_count = call_param_count[fn_token];
    if (ordinal == INVALID || ordinal >= param_count)
        return false;
    local_index = function_param_abi_ordinal(fn_token, ordinal);
    if (local_index == INVALID)
        return false;
    return true;
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

uint direct_call_arg_abi_len(uint node, uint param_ty)
{
    return param_ty == TY_STRING ? string_value_expr_len(node) : expr_len(node);
}

uint direct_call_arg_abi_byte(uint node, uint param_ty, uint byte_i)
{
    return param_ty == TY_STRING ? string_value_expr_byte(node, byte_i) : expr_byte(node, byte_i);
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
        return 1u + u32_leb_len(local_index);
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

uint method_member_node_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return callee_node;

    callee_node = resolve_expr_node(callee_node);
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR
               ? callee_node
               : INVALID;
}

uint method_receiver_node_for_call(uint call_node)
{
    uint member_node = method_member_node_for_call(call_node);
    if (!valid_node(member_node))
        return INVALID;
    uint receiver_node = hir_member_receiver_node[member_node];
    return valid_node(receiver_node) ? receiver_node : INVALID;
}

bool direct_call_record_has_receiver_arg(uint call_node, uint fn_token, uint arg_count)
{
    if (!valid_token(fn_token))
        return false;
    uint receiver_node = method_receiver_node_for_call(call_node);
    if (!valid_node(receiver_node))
        return false;
    uint explicit_arg_count = hir_call_arg_count[call_node];
    return arg_count == explicit_arg_count + 1u &&
           call_param_count[fn_token] == arg_count;
}

uint direct_call_abi_arg_node(uint call_node, uint fn_token, uint arg_count, uint ordinal)
{
    if (direct_call_record_has_receiver_arg(call_node, fn_token, arg_count))
    {
        if (ordinal == 0u)
            return method_receiver_node_for_call(call_node);
        return direct_call_arg_node(call_node, ordinal - 1u);
    }
    return direct_call_arg_node(call_node, ordinal);
}

uint assign_op_byte(uint op)
{
    if (op == ASSIGN_OP_ADD) return WASM_I32_ADD;
    if (op == ASSIGN_OP_SUB) return WASM_I32_SUB;
    if (op == ASSIGN_OP_MUL) return WASM_I32_MUL;
    if (op == ASSIGN_OP_DIV) return WASM_I32_DIV_S;
    if (op == ASSIGN_OP_MOD) return WASM_I32_REM_S;
    return 0u;
}

uint let_direct_call_i32_fragment_byte(uint local_index, uint call_node, uint4 aux, uint fragment_len, uint byte_i)
{
    uint set_len = local_set_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i >= call_len)
        return local_set_byte(local_index, byte_i - call_len);

    uint wasm_func_index = aux.x;
    uint tail_len = 1u + wasm_call_index_len(wasm_func_index);
    uint arg_len = call_len > tail_len ? call_len - tail_len : 0u;
    if (byte_i < arg_len)
        return 0u;
    if (byte_i == arg_len)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - arg_len - 1u);
}

uint assign_direct_call_i32_fragment_byte(uint local_index, uint call_node, uint4 aux, uint fragment_len, uint byte_i)
{
    return let_direct_call_i32_fragment_byte(local_index, call_node, aux, fragment_len, byte_i);
}

uint assign_compound_direct_call_i32_fragment_byte(uint local_index, uint call_node, uint op, uint4 aux, uint fragment_len, uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    uint get_len = local_get_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);

    uint call_start = get_len;
    uint set_len = local_set_len(local_index);
    uint suffix_len = 1u + set_len;
    uint call_len = fragment_len > call_start + suffix_len
                        ? fragment_len - call_start - suffix_len
                        : 0u;
    if (byte_i < call_start + call_len)
    {
        uint call_byte_i = byte_i - call_start;
        uint wasm_func_index = aux.x;
        uint tail_len = 1u + wasm_call_index_len(wasm_func_index);
        uint arg_len = call_len > tail_len ? call_len - tail_len : 0u;
        if (call_byte_i < arg_len)
            return 0u;
        if (call_byte_i == arg_len)
            return WASM_CALL;
        return wasm_call_index_byte(wasm_func_index, call_byte_i - arg_len - 1u);
    }

    uint op_i = call_start + call_len;
    if (byte_i == op_i)
        return assign_op_byte(op);

    return local_set_byte(local_index, byte_i - op_i - 1u);
}

uint return_direct_call_i32_fragment_byte(uint call_node, uint4 aux, uint fragment_len, uint byte_i)
{
    uint call_len = fragment_len > 0u ? fragment_len - 1u : 0u;
    if (byte_i >= call_len)
        return WASM_RETURN;

    uint wasm_func_index = aux.x;
    uint tail_len = 1u + wasm_call_index_len(wasm_func_index);
    uint arg_len = call_len > tail_len ? call_len - tail_len : 0u;
    if (byte_i < arg_len)
        return 0u;
    if (byte_i == arg_len)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - arg_len - 1u);
}

uint print_direct_call_i64_fragment_byte(uint call_node, uint4 aux, uint fragment_len, uint byte_i)
{
    uint suffix_len = 3u;
    uint call_len = fragment_len > suffix_len ? fragment_len - suffix_len : 0u;
    if (byte_i >= call_len)
    {
        uint suffix_i = byte_i - call_len;
        if (suffix_i == 0u)
            return WASM_I64_EXTEND_I32_S;
        if (suffix_i == 1u)
            return WASM_CALL;
        return WASM_PRINT_I64_FUNC_INDEX;
    }

    uint wasm_func_index = aux.x;
    uint tail_len = 1u + wasm_call_index_len(wasm_func_index);
    uint arg_len = call_len > tail_len ? call_len - tail_len : 0u;
    if (byte_i < arg_len)
        return 0u;
    if (byte_i == arg_len)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - arg_len - 1u);
}

uint direct_call_void_fragment_byte(uint4 aux, uint fragment_len, uint byte_i)
{
    uint wasm_func_index = aux.x;
    uint tail_len = 1u + wasm_call_index_len(wasm_func_index);
    uint arg_len = fragment_len > tail_len ? fragment_len - tail_len : 0u;
    if (byte_i < arg_len)
        return 0u;
    if (byte_i == arg_len)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - arg_len - 1u);
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
    if (meta.x != BODY_FRAGMENT_LET_DIRECT_CALL_I32 &&
        meta.x != BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 &&
        meta.x != BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 &&
        meta.x != BODY_FRAGMENT_DIRECT_CALL_VOID &&
        meta.x != BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 &&
        meta.x != BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
        return;

    uint byte_i = body_byte_i - offset;
    uint4 aux = body_fragment_aux[token_i];
    if (meta.x == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32)
    {
        body_words[offset + byte_i] = assign_direct_call_i32_fragment_byte(meta.y, meta.z, aux, len, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
    {
        body_words[offset + byte_i] = assign_compound_direct_call_i32_fragment_byte(meta.y, meta.z, meta.w, aux, len, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64)
    {
        body_words[offset + byte_i] = print_direct_call_i64_fragment_byte(meta.y, aux, len, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_DIRECT_CALL_VOID)
    {
        body_words[offset + byte_i] = direct_call_void_fragment_byte(aux, len, byte_i);
        return;
    }
    body_words[offset + byte_i] =
        meta.x == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32
            ? return_direct_call_i32_fragment_byte(meta.y, aux, len, byte_i)
            : let_direct_call_i32_fragment_byte(meta.y, meta.z, aux, len, byte_i);
}
