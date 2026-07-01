// Scatter scanned WASM body fragments into the body byte stream.

import gpu_index;
import prefix_scan;

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
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_nearest_enclosing_control_node;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LOCAL_DECL_COUNT = 1u;
static const uint BODY_FRAGMENT_PRINT_I64 = 2u;
static const uint BODY_FRAGMENT_RETURN_I32 = 3u;
static const uint BODY_FRAGMENT_LET_CONST_I32 = 4u;
static const uint BODY_FRAGMENT_ASSIGN_CONST_I32 = 5u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32 = 6u;
static const uint BODY_FRAGMENT_PRINT_LOCAL_I64 = 7u;
static const uint BODY_FRAGMENT_RETURN_LOCAL_I32 = 8u;
static const uint BODY_FRAGMENT_LET_EXPR_I32 = 9u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_I32 = 10u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 = 11u;
static const uint BODY_FRAGMENT_PRINT_EXPR_I64 = 12u;
static const uint BODY_FRAGMENT_RETURN_EXPR_I32 = 13u;
static const uint BODY_FRAGMENT_WHILE_OPEN_I32 = 14u;
static const uint BODY_FRAGMENT_WHILE_CLOSE = 15u;
static const uint BODY_FRAGMENT_IF_OPEN_I32 = 16u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint BODY_FRAGMENT_BRANCH = 19u;
static const uint BODY_FRAGMENT_FOR_OPEN_RANGE_I32 = 20u;
static const uint BODY_FRAGMENT_FOR_CLOSE_RANGE_I32 = 21u;
static const uint BODY_FRAGMENT_FUNCTION_HEADER = 22u;
static const uint BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 = 23u;
static const uint BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 = 24u;
static const uint BODY_FRAGMENT_LET_DIRECT_CALL_I32 = 25u;
static const uint BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 = 26u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 = 27u;
static const uint BODY_FRAGMENT_FUNCTION_END = 28u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WASM_WRITE_STDOUT_FUNC_INDEX = 1u;
static const uint BODY_FRAGMENT_LET_HOST_STDOUT_WRITE_I32 = 32u;
static const uint BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR = 33u;
static const uint BODY_FRAGMENT_LET_HOST_NO_ARG_I32 = 34u;
static const uint BODY_FRAGMENT_LET_PROCESS_ARG_LEN_I32 = 35u;
static const uint BODY_FRAGMENT_LET_PROCESS_ARG_READ_I32 = 36u;
static const uint WASM_PROCESS_ARGC_FUNC_INDEX = 2u;
static const uint WASM_PROCESS_ARG_LEN_FUNC_INDEX = 3u;
static const uint WASM_PROCESS_ARG_READ_FUNC_INDEX = 4u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint WASM_MAX_DIRECT_CALL_ARGS = 4u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint HIR_STMT = 7u;
static const uint HIR_FOR_STMT = 30u;
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
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WASM_UNREACHABLE = 0x00u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_CONST = 0x42u;
static const uint WASM_BLOCK = 0x02u;
static const uint WASM_LOOP = 0x03u;
static const uint WASM_IF = 0x04u;
static const uint WASM_ELSE = 0x05u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_BR = 0x0cu;
static const uint WASM_BR_IF = 0x0du;
static const uint WASM_RETURN = 0x0fu;
static const uint WASM_CALL = 0x10u;
static const uint WASM_END = 0x0bu;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I32_EQ = 0x46u;
static const uint WASM_I32_NE = 0x47u;
static const uint WASM_I32_LT_S = 0x48u;
static const uint WASM_I32_GT_S = 0x4au;
static const uint WASM_I32_LE_S = 0x4cu;
static const uint WASM_I32_GE_S = 0x4eu;
static const uint WASM_I64_EXTEND_I32_S = 0xacu;
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
static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint WG_SIZE = 256u;
static const uint BODY_FRAGMENT_MAX_BYTES = 32u;
static const uint MAX_CONTROL_BRANCH_DEPTH = 16u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gScan.n_items;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
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

bool function_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    uint param_count = call_param_count[fn_token];
    if (ordinal == INVALID || ordinal >= param_count)
        return false;
    local_index = ordinal;
    return true;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint param_count = call_param_count[fn_token];
    if (param_count > WASM_MAX_DIRECT_CALL_ARGS)
        return false;
    local_index = param_count + decl_token;
    return true;
}

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return node == INVALID ? HIR_EXPR_NONE : expr_record_slot(node, EXPR_RECORD_FORM);
}

uint resolve_expr_node(uint node)
{
    if (node == INVALID)
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    if (root != INVALID)
        return root;
    return expr_form(node) == HIR_EXPR_FORWARD ? INVALID : node;
}

uint i32_sleb_len(uint value)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (done)
            return i + 1u;
    }
    return 5u;
}

uint i32_sleb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (!done)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (done)
            return 0u;
    }
    return 0u;
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
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (value == 0u)
            return 0u;
    }
    return 0u;
}

uint u32_leb5_byte(uint value, uint byte_i)
{
    uint byte_value = (value >> (byte_i * 7u)) & 0x7fu;
    if (byte_i < 4u)
        byte_value |= 0x80u;
    return byte_value;
}

uint local_decl_fragment_byte(uint local_count, uint byte_i)
{
    if (local_count == 0u)
        return 0u;
    if (byte_i == 0u)
        return 1u;
    uint count_len = u32_leb_len(local_count);
    if (byte_i <= count_len)
        return u32_leb_byte(local_count, byte_i - 1u);
    return 0x7fu;
}

uint function_header_fragment_byte(uint body_size, uint local_count, uint byte_i)
{
    if (byte_i < 5u)
        return u32_leb5_byte(body_size, byte_i);
    return local_decl_fragment_byte(local_count, byte_i - 5u);
}

uint i32_const_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;
    return i32_sleb_byte(value, byte_i - 1u);
}

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

bool local_decl_token_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    node = resolve_expr_node(node);
    if (node == INVALID || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;
    uint owner_fn = node_enclosing_fn_token(node);
    uint local_index = INVALID;
    if (function_param_local_index(decl_token, owner_fn, local_index))
    {
        decl_token = local_index;
        return true;
    }
    if (body_let_init_expr_by_decl_token[decl_token] != INVALID)
    {
        if (!function_non_param_local_index(decl_token, owner_fn, local_index))
            return false;
        decl_token = local_index;
        return true;
    }

    uint control = hir_nearest_enclosing_control_node[node];
    for (uint i = 0u; i < MAX_CONTROL_BRANCH_DEPTH; i += 1u)
    {
        if (control == INVALID)
            return false;
        if ((hir_kind[control] == HIR_FOR_STMT || hir_kind[control] == HIR_STMT) &&
            stmt_record_slot(control, 0u) == STMT_RECORD_KIND_FOR &&
            stmt_record_slot(control, 1u) == decl_token)
        {
            if (!function_non_param_local_index(decl_token, owner_fn, local_index))
                return false;
            decl_token = local_index;
            return true;
        }
        control = hir_nearest_enclosing_control_node[control];
    }
    return false;
}

bool name_const_record_value(uint node, out uint value)
{
    value = 0u;
    if (node == INVALID || expr_form(node) != HIR_EXPR_NAME)
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

uint direct_call_arg_node(uint call_node, uint ordinal)
{
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

uint expr_binary_op_byte(uint form)
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
    if (form == HIR_EXPR_AND || form == HIR_EXPR_BIT_AND) return WASM_I32_AND;
    if (form == HIR_EXPR_OR || form == HIR_EXPR_BIT_OR) return WASM_I32_OR;
    if (form == HIR_EXPR_BIT_XOR) return WASM_I32_XOR;
    if (form == HIR_EXPR_SHL) return WASM_I32_SHL;
    if (form == HIR_EXPR_SHR) return WASM_I32_SHR_S;
    if (form == HIR_EXPR_DIV) return WASM_I32_DIV_S;
    if (form == HIR_EXPR_MOD) return WASM_I32_REM_S;
    return 0u;
}

bool const_atom_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (node == INVALID)
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
    if (node == INVALID)
        return false;

    if (const_atom_value(node, value))
        return true;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint inner = 0u;
        if (!const_atom_value(expr_record_slot(node, EXPR_RECORD_LEFT), inner))
            return false;
        return unary_const_value(form, inner, value);
    }
    return false;
}

uint expr_non_call_atom_len(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return 0u;

    uint form = expr_form(node);
    uint decl_token = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, decl_token))
        return 1u + u32_leb_len(decl_token);
    uint const_value = 0u;
    if (form == HIR_EXPR_NAME && name_const_record_value(node, const_value))
        return 1u + i32_sleb_len(const_value);
    if (form == HIR_EXPR_INT)
        return 1u + i32_sleb_len(hir_expr_int_value[node]);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return 2u;
    return 0u;
}

uint direct_call_arg_len(uint node)
{
    uint expr_len = expr_simple_len(node);
    if (expr_len != 0u)
        return expr_len;

    uint value = 0u;
    return direct_call_arg_const_value(node, value) ? 1u + i32_sleb_len(value) : 0u;
}

uint direct_call_arg_scalar_len(uint node)
{
    uint atom_len = expr_non_call_atom_len(node);
    if (atom_len != 0u)
        return atom_len;

    uint value = 0u;
    return direct_call_arg_const_value(node, value) ? 1u + i32_sleb_len(value) : 0u;
}

uint expr_atom_len(uint node)
{
    return expr_non_call_atom_len(node);
}

uint expr_simple_len(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return 0u;

    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return atom_len;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
    {
        uint inner_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
        return inner_len == 0u ? 0u : inner_len + 1u;
    }
    if (form == HIR_EXPR_NEG)
    {
        uint inner_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
        return inner_len == 0u ? 0u : inner_len + 3u;
    }

    uint op = expr_binary_op_byte(form);
    if (op == 0u)
        return 0u;
    uint left_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
    uint right_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT));
    return left_len == 0u || right_len == 0u ? 0u : left_len + right_len + 1u;
}

uint expr_non_call_atom_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint form = expr_form(node);
    uint decl_token = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, decl_token))
        return local_get_byte(decl_token, byte_i);
    uint const_value = 0u;
    if (form == HIR_EXPR_NAME && name_const_record_value(node, const_value))
        return i32_const_byte(const_value, byte_i);
    if (form == HIR_EXPR_INT)
        return i32_const_byte(hir_expr_int_value[node], byte_i);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
    return 0u;
}

uint direct_call_arg_byte(uint node, uint byte_i)
{
    uint expr_len = expr_simple_len(node);
    if (expr_len != 0u)
        return expr_simple_byte(node, byte_i);

    uint value = 0u;
    if (!direct_call_arg_const_value(node, value))
        return 0u;
    return i32_const_byte(value, byte_i);
}

uint direct_call_arg_scalar_byte(uint node, uint byte_i)
{
    uint atom_len = expr_non_call_atom_len(node);
    if (atom_len != 0u)
        return expr_non_call_atom_byte(node, byte_i);

    uint value = 0u;
    if (!direct_call_arg_const_value(node, value))
        return 0u;
    return i32_const_byte(value, byte_i);
}

uint direct_call_expr_byte_from_record(
    uint node,
    uint wasm_func_index,
    uint arg_count,
    uint byte_i)
{
    node = resolve_expr_node(node);
    if (wasm_func_index == INVALID || arg_count > WASM_MAX_DIRECT_CALL_ARGS)
        return 0u;

    uint offset = 0u;
    for (uint i = 0u; i < WASM_MAX_DIRECT_CALL_ARGS; i += 1u)
    {
        if (i >= arg_count)
            continue;
        uint arg_node = direct_call_arg_node(node, i);
        uint arg_len = direct_call_arg_len(arg_node);
        if (byte_i < offset + arg_len)
            return direct_call_arg_byte(arg_node, byte_i - offset);
        offset += arg_len;
    }

    if (byte_i == offset)
        return WASM_CALL;
    return u32_leb_byte(wasm_func_index, byte_i - offset - 1u);
}

uint direct_call_expr_scalar_byte_from_record(
    uint node,
    uint wasm_func_index,
    uint arg_count,
    uint byte_i)
{
    node = resolve_expr_node(node);
    if (wasm_func_index == INVALID || arg_count > WASM_MAX_DIRECT_CALL_ARGS)
        return 0u;

    uint offset = 0u;
    for (uint i = 0u; i < WASM_MAX_DIRECT_CALL_ARGS; i += 1u)
    {
        if (i >= arg_count)
            continue;
        uint arg_node = direct_call_arg_node(node, i);
        uint arg_len = direct_call_arg_scalar_len(arg_node);
        if (byte_i < offset + arg_len)
            return direct_call_arg_scalar_byte(arg_node, byte_i - offset);
        offset += arg_len;
    }

    if (byte_i == offset)
        return WASM_CALL;
    return u32_leb_byte(wasm_func_index, byte_i - offset - 1u);
}

uint direct_call_expr_len_from_record(
    uint node,
    uint wasm_func_index,
    uint arg_count)
{
    node = resolve_expr_node(node);
    if (wasm_func_index == INVALID || arg_count > WASM_MAX_DIRECT_CALL_ARGS)
        return 0u;

    uint total = 1u + u32_leb_len(wasm_func_index);
    for (uint i = 0u; i < WASM_MAX_DIRECT_CALL_ARGS; i += 1u)
    {
        if (i >= arg_count)
            continue;
        uint arg_len = direct_call_arg_len(direct_call_arg_node(node, i));
        if (arg_len == 0u)
            return 0u;
        total += arg_len;
    }
    return total;
}

uint expr_atom_byte(uint node, uint byte_i)
{
    return expr_non_call_atom_byte(node, byte_i);
}

uint expr_simple_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return expr_atom_byte(node, byte_i);

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
    {
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = expr_atom_len(inner);
        if (byte_i < inner_len)
            return expr_atom_byte(inner, byte_i);
        return WASM_I32_EQZ;
    }
    if (form == HIR_EXPR_NEG)
    {
        if (byte_i < 2u)
            return i32_const_byte(0u, byte_i);
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = expr_atom_len(inner);
        if (byte_i < 2u + inner_len)
            return expr_atom_byte(inner, byte_i - 2u);
        return WASM_I32_SUB;
    }

    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint left_len = expr_atom_len(left);
    uint right_len = expr_atom_len(right);
    if (byte_i < left_len)
        return expr_atom_byte(left, byte_i);
    if (byte_i < left_len + right_len)
        return expr_atom_byte(right, byte_i - left_len);
    return expr_binary_op_byte(form);
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

uint print_i64_fragment_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I64_CONST;

    uint value_len = i32_sleb_len(value);
    if (byte_i <= value_len)
        return i32_sleb_byte(value, byte_i - 1u);

    if (byte_i == value_len + 1u)
        return WASM_CALL;

    return WASM_PRINT_I64_FUNC_INDEX;
}

uint print_local_i64_fragment_byte(uint local_index, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);
    if (byte_i == get_len)
        return WASM_I64_EXTEND_I32_S;
    if (byte_i == get_len + 1u)
        return WASM_CALL;
    return WASM_PRINT_I64_FUNC_INDEX;
}

uint return_i32_fragment_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;

    uint value_len = i32_sleb_len(value);
    if (byte_i <= value_len)
        return i32_sleb_byte(value, byte_i - 1u);

    return WASM_RETURN;
}

uint return_local_i32_fragment_byte(uint local_index, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);
    return WASM_RETURN;
}

uint let_const_i32_fragment_byte(uint local_index, uint value, uint byte_i)
{
    uint const_len = 1u + i32_sleb_len(value);
    if (byte_i < const_len)
        return i32_const_byte(value, byte_i);
    return local_set_byte(local_index, byte_i - const_len);
}

uint assign_const_i32_fragment_byte(uint local_index, uint value, uint byte_i)
{
    return let_const_i32_fragment_byte(local_index, value, byte_i);
}

uint assign_compound_const_i32_fragment_byte(uint local_index, uint value, uint op, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);

    uint const_start = get_len;
    uint const_len = 1u + i32_sleb_len(value);
    if (byte_i < const_start + const_len)
        return i32_const_byte(value, byte_i - const_start);

    uint op_i = const_start + const_len;
    if (byte_i == op_i)
        return assign_op_byte(op);

    return local_set_byte(local_index, byte_i - op_i - 1u);
}

uint let_expr_i32_fragment_byte(uint local_index, uint expr_node, uint byte_i)
{
    uint expr_len = expr_simple_len(expr_node);
    if (byte_i < expr_len)
        return expr_simple_byte(expr_node, byte_i);
    return local_set_byte(local_index, byte_i - expr_len);
}

uint assign_expr_i32_fragment_byte(uint local_index, uint expr_node, uint byte_i)
{
    return let_expr_i32_fragment_byte(local_index, expr_node, byte_i);
}

uint assign_compound_expr_i32_fragment_byte(uint local_index, uint expr_node, uint op, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);

    uint expr_start = get_len;
    uint expr_len = expr_simple_len(expr_node);
    if (byte_i < expr_start + expr_len)
        return expr_simple_byte(expr_node, byte_i - expr_start);

    uint op_i = expr_start + expr_len;
    if (byte_i == op_i)
        return assign_op_byte(op);

    return local_set_byte(local_index, byte_i - op_i - 1u);
}

uint print_expr_i64_fragment_byte(uint expr_node, uint byte_i)
{
    uint expr_len = expr_simple_len(expr_node);
    if (byte_i < expr_len)
        return expr_simple_byte(expr_node, byte_i);
    if (byte_i == expr_len)
        return WASM_I64_EXTEND_I32_S;
    if (byte_i == expr_len + 1u)
        return WASM_CALL;
    return WASM_PRINT_I64_FUNC_INDEX;
}

uint return_expr_i32_fragment_byte(uint expr_node, uint byte_i)
{
    uint expr_len = expr_simple_len(expr_node);
    if (byte_i < expr_len)
        return expr_simple_byte(expr_node, byte_i);
    return WASM_RETURN;
}

uint let_direct_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    uint set_len = 1u + u32_leb_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i < call_len)
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, byte_i);
    return local_set_byte(local_index, byte_i - call_len);
}

uint let_host_process_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint wasm_func_index,
    uint arg_count,
    uint fragment_len,
    uint byte_i)
{
    uint set_len = 1u + u32_leb_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i < call_len)
        return direct_call_expr_scalar_byte_from_record(
            call_node,
            wasm_func_index,
            arg_count,
            byte_i);
    return local_set_byte(local_index, byte_i - call_len);
}

uint i32_array_data_ptr_expr_byte(uint call_node, uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    return direct_call_arg_scalar_byte(direct_call_arg_node(call_node, 0u), byte_i);
}

uint let_i32_array_data_ptr_fragment_byte(
    uint local_index,
    uint call_node,
    uint fragment_len,
    uint byte_i)
{
    uint set_len = 1u + u32_leb_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i < call_len)
        return i32_array_data_ptr_expr_byte(call_node, byte_i);
    return local_set_byte(local_index, byte_i - call_len);
}

uint assign_direct_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    return let_direct_call_i32_fragment_byte(local_index, call_node, aux, fragment_len, byte_i);
}

uint assign_compound_direct_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint op,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);

    uint call_start = get_len;
    uint set_len = 1u + u32_leb_len(local_index);
    uint suffix_len = 1u + set_len;
    uint call_len = fragment_len > call_start + suffix_len
                        ? fragment_len - call_start - suffix_len
                        : 0u;
    if (byte_i < call_start + call_len)
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, byte_i - call_start);

    uint op_i = call_start + call_len;
    if (byte_i == op_i)
        return assign_op_byte(op);

    return local_set_byte(local_index, byte_i - op_i - 1u);
}

uint print_direct_call_i64_fragment_byte(
    uint call_node,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    uint call_len = fragment_len > 3u ? fragment_len - 3u : 0u;
    if (byte_i < call_len)
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, byte_i);
    if (byte_i == call_len)
        return WASM_I64_EXTEND_I32_S;
    if (byte_i == call_len + 1u)
        return WASM_CALL;
    return WASM_PRINT_I64_FUNC_INDEX;
}

uint return_direct_call_i32_fragment_byte(
    uint call_node,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    uint call_len = fragment_len > 0u ? fragment_len - 1u : 0u;
    if (byte_i < call_len)
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, byte_i);
    return WASM_RETURN;
}

uint return_binary_direct_call_i32_fragment_byte(
    uint call_node,
    uint atom_node,
    uint packed_op,
    uint4 aux,
    uint byte_i)
{
    uint op = packed_op & 0xffu;
    uint call_side = packed_op >> 8u;
    uint atom_len = expr_atom_len(atom_node);
    uint call_len = direct_call_expr_len_from_record(call_node, aux.x, aux.y);

    if (call_side == 0u)
    {
        if (byte_i < call_len)
            return direct_call_expr_byte_from_record(call_node, aux.x, aux.y, byte_i);
        if (byte_i < call_len + atom_len)
            return expr_atom_byte(atom_node, byte_i - call_len);
        if (byte_i == call_len + atom_len)
            return op;
        return WASM_RETURN;
    }

    if (byte_i < atom_len)
        return expr_atom_byte(atom_node, byte_i);
    if (byte_i < atom_len + call_len)
        return direct_call_expr_byte_from_record(call_node, aux.x, aux.y, byte_i - atom_len);
    if (byte_i == atom_len + call_len)
        return op;
    return WASM_RETURN;
}

uint while_open_i32_fragment_byte(uint condition_node, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BLOCK;
    if (byte_i == 1u)
        return WASM_BLOCK_TYPE_EMPTY;
    if (byte_i == 2u)
        return WASM_LOOP;
    if (byte_i == 3u)
        return WASM_BLOCK_TYPE_EMPTY;

    uint condition_start = 4u;
    uint condition_len = expr_simple_len(condition_node);
    if (byte_i < condition_start + condition_len)
        return expr_simple_byte(condition_node, byte_i - condition_start);

    uint eqz_i = condition_start + condition_len;
    if (byte_i == eqz_i)
        return WASM_I32_EQZ;
    if (byte_i == eqz_i + 1u)
        return WASM_BR_IF;
    return 1u;
}

uint while_close_fragment_byte(uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BR;
    if (byte_i == 1u)
        return 0u;
    return WASM_END;
}

uint if_open_i32_fragment_byte(uint condition_node, uint byte_i)
{
    uint condition_len = expr_simple_len(condition_node);
    if (byte_i < condition_len)
        return expr_simple_byte(condition_node, byte_i);
    if (byte_i == condition_len)
        return WASM_IF;
    return WASM_BLOCK_TYPE_EMPTY;
}

uint branch_fragment_byte(uint depth, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BR;
    return u32_leb_byte(depth, byte_i - 1u);
}

uint for_range_start_node(uint range_node)
{
    return expr_record_slot(resolve_expr_node(range_node), EXPR_RECORD_LEFT);
}

uint for_range_end_node(uint range_node)
{
    return expr_record_slot(resolve_expr_node(range_node), EXPR_RECORD_RIGHT);
}

uint for_open_range_i32_fragment_byte(uint binding_token, uint range_node, uint end_local_token, uint byte_i)
{
    uint start_node = for_range_start_node(range_node);
    uint start_len = expr_simple_len(start_node);
    if (byte_i < start_len)
        return expr_simple_byte(start_node, byte_i);

    uint binding_set_start = start_len;
    uint binding_set_len = 1u + u32_leb_len(binding_token);
    if (byte_i < binding_set_start + binding_set_len)
        return local_set_byte(binding_token, byte_i - binding_set_start);

    uint end_node = for_range_end_node(range_node);
    uint end_start = binding_set_start + binding_set_len;
    uint end_len = expr_simple_len(end_node);
    if (byte_i < end_start + end_len)
        return expr_simple_byte(end_node, byte_i - end_start);

    uint end_set_start = end_start + end_len;
    uint end_set_len = 1u + u32_leb_len(end_local_token);
    if (byte_i < end_set_start + end_set_len)
        return local_set_byte(end_local_token, byte_i - end_set_start);

    uint block_start = end_set_start + end_set_len;
    if (byte_i == block_start + 0u)
        return WASM_BLOCK;
    if (byte_i == block_start + 1u)
        return WASM_BLOCK_TYPE_EMPTY;
    if (byte_i == block_start + 2u)
        return WASM_LOOP;
    if (byte_i == block_start + 3u)
        return WASM_BLOCK_TYPE_EMPTY;

    uint condition_start = block_start + 4u;
    uint binding_get_len = 1u + u32_leb_len(binding_token);
    if (byte_i < condition_start + binding_get_len)
        return local_get_byte(binding_token, byte_i - condition_start);

    uint end_get_start = condition_start + binding_get_len;
    uint end_get_len = 1u + u32_leb_len(end_local_token);
    if (byte_i < end_get_start + end_get_len)
        return local_get_byte(end_local_token, byte_i - end_get_start);

    uint ge_i = end_get_start + end_get_len;
    if (byte_i == ge_i)
        return WASM_I32_GE_S;
    if (byte_i == ge_i + 1u)
        return WASM_BR_IF;
    if (byte_i == ge_i + 2u)
        return 1u;
    if (byte_i == ge_i + 3u)
        return WASM_BLOCK;
    return WASM_BLOCK_TYPE_EMPTY;
}

uint for_close_range_i32_fragment_byte(uint binding_token, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_END;

    uint get_start = 1u;
    uint get_len = 1u + u32_leb_len(binding_token);
    if (byte_i < get_start + get_len)
        return local_get_byte(binding_token, byte_i - get_start);

    uint one_start = get_start + get_len;
    if (byte_i < one_start + 2u)
        return i32_const_byte(1u, byte_i - one_start);

    uint add_i = one_start + 2u;
    if (byte_i == add_i)
        return WASM_I32_ADD;

    uint set_start = add_i + 1u;
    uint set_len = 1u + u32_leb_len(binding_token);
    if (byte_i < set_start + set_len)
        return local_set_byte(binding_token, byte_i - set_start);

    uint br_i = set_start + set_len;
    if (byte_i == br_i)
        return WASM_BR;
    if (byte_i == br_i + 1u)
        return 0u;
    if (byte_i == br_i + 2u)
        return WASM_END;
    return WASM_END;
}

uint fragment_byte(uint4 meta, uint4 aux, uint fragment_len, uint byte_i)
{
    uint kind = meta.x;
    uint value = meta.y;

    if (kind == BODY_FRAGMENT_LOCAL_DECL_COUNT)
        return local_decl_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_FUNCTION_HEADER)
        return function_header_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_FUNCTION_END)
        return byte_i == 0u ? WASM_UNREACHABLE : WASM_END;
    if (kind == BODY_FRAGMENT_PRINT_I64)
        return print_i64_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_I32)
        return return_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_LET_CONST_I32)
        return let_const_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_CONST_I32)
        return assign_const_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32)
        return assign_compound_const_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
    if (kind == BODY_FRAGMENT_PRINT_LOCAL_I64)
        return print_local_i64_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_LOCAL_I32)
        return return_local_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_LET_EXPR_I32)
        return let_expr_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_EXPR_I32)
        return assign_expr_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32)
        return assign_compound_expr_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
    if (kind == BODY_FRAGMENT_PRINT_EXPR_I64)
        return print_expr_i64_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_EXPR_I32)
        return return_expr_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64)
        return print_direct_call_i64_fragment_byte(value, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32)
        return return_direct_call_i32_fragment_byte(value, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32)
        return return_binary_direct_call_i32_fragment_byte(meta.y, meta.z, meta.w, aux, byte_i);
    if (kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32)
        return let_direct_call_i32_fragment_byte(meta.y, meta.z, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_LET_HOST_STDOUT_WRITE_I32)
        return let_host_process_call_i32_fragment_byte(
            meta.y,
            meta.z,
            WASM_WRITE_STDOUT_FUNC_INDEX,
            2u,
            fragment_len,
            byte_i);
    if (kind == BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR)
        return let_i32_array_data_ptr_fragment_byte(meta.y, meta.z, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_LET_HOST_NO_ARG_I32)
        return let_host_process_call_i32_fragment_byte(
            meta.y,
            meta.z,
            meta.w,
            0u,
            fragment_len,
            byte_i);
    if (kind == BODY_FRAGMENT_LET_PROCESS_ARG_LEN_I32)
        return let_host_process_call_i32_fragment_byte(
            meta.y,
            meta.z,
            WASM_PROCESS_ARG_LEN_FUNC_INDEX,
            1u,
            fragment_len,
            byte_i);
    if (kind == BODY_FRAGMENT_LET_PROCESS_ARG_READ_I32)
        return let_host_process_call_i32_fragment_byte(
            meta.y,
            meta.z,
            WASM_PROCESS_ARG_READ_FUNC_INDEX,
            3u,
            fragment_len,
            byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32)
        return assign_direct_call_i32_fragment_byte(meta.y, meta.z, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
        return assign_compound_direct_call_i32_fragment_byte(meta.y, meta.z, meta.w, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_WHILE_OPEN_I32)
        return while_open_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_WHILE_CLOSE)
        return while_close_fragment_byte(byte_i);
    if (kind == BODY_FRAGMENT_IF_OPEN_I32)
        return if_open_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_IF_ELSE)
        return WASM_ELSE;
    if (kind == BODY_FRAGMENT_IF_END)
        return WASM_END;
    if (kind == BODY_FRAGMENT_BRANCH)
        return branch_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_FOR_OPEN_RANGE_I32)
        return for_open_range_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
    if (kind == BODY_FRAGMENT_FOR_CLOSE_RANGE_I32)
        return for_close_range_i32_fragment_byte(value, byte_i);

    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot_i = linear_dispatch_id(tid);
    uint token_i = slot_i / BODY_FRAGMENT_MAX_BYTES;
    uint byte_i = slot_i - token_i * BODY_FRAGMENT_MAX_BYTES;
    if (token_i >= gScan.n_items || status[2u] != 0u)
        return;

    uint len = body_fragment_len[token_i];
    if (byte_i >= len)
        return;

    uint offset = body_prefix_for_token(token_i);
    uint4 meta = body_fragment_meta[token_i];
    uint4 aux = body_fragment_aux[token_i];
    body_words[offset + byte_i] = fragment_byte(meta, aux, len, byte_i);
}
