// Scatter scanned WASM body fragments into the body byte stream.

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
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_stmt_record;
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
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
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
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;

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
static const uint BODY_FRAGMENT_LET_HOST_CALL_I32 = 37u;
static const uint BODY_FRAGMENT_HOST_CALL_VOID = 38u;
static const uint BODY_FRAGMENT_LET_HOST_STR_CALL_I32 = 39u;
static const uint WASM_PROCESS_ARGC_FUNC_INDEX = 2u;
static const uint WASM_PROCESS_ARG_LEN_FUNC_INDEX = 3u;
static const uint WASM_PROCESS_ARG_READ_FUNC_INDEX = 4u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
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
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WASM_UNREACHABLE = 0x00u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_CONST = 0x42u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
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
static const uint WASM_F32_EQ = 0x5bu;
static const uint WASM_F32_NE = 0x5cu;
static const uint WASM_F32_LT = 0x5du;
static const uint WASM_F32_GT = 0x5eu;
static const uint WASM_F32_LE = 0x5fu;
static const uint WASM_F32_GE = 0x60u;
static const uint WASM_F32_NEG = 0x8cu;
static const uint WASM_F32_ADD = 0x92u;
static const uint WASM_F32_SUB = 0x93u;
static const uint WASM_F32_MUL = 0x94u;
static const uint WASM_F32_DIV = 0x95u;
static const uint WASM_VALTYPE_F32 = 0x7du;
static const uint WASM_VALTYPE_I32 = 0x7fu;
static const uint HOST_STR_CALL_OPEN_READ_PATH = 1u;
static const uint HOST_STR_CALL_OPEN_WRITE_PATH = 2u;
static const uint HOST_STR_CALL_WRITE_TEXT = 3u;
static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint WG_SIZE = 256u;
static const uint BODY_FRAGMENT_MAX_BYTES = 32u;
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
    local_index = function_param_abi_ordinal(fn_token, ordinal);
    if (local_index == INVALID)
        return false;
    return true;
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

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint param_count = function_param_abi_count(fn_token);
    uint local_count = 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    if (local_max != INVALID)
        local_count = local_max + 1u;
    local_index = param_count + decl_token;
    if (local_decl_type(decl_token) == TY_FLOAT)
        local_index += local_count * 2u;
    return true;
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

uint local_decl_initializer_type(uint decl_token)
{
    uint init_expr = valid_token(decl_token) ? body_let_init_expr_by_decl_token[decl_token] : INVALID;
    if (!valid_node(init_expr))
        return TY_UNKNOWN;
    uint root = hir_expr_result_root_node[init_expr];
    if (valid_node(root))
        init_expr = root;
    uint form = row_major_load<uint>(
        hir_expr_record,
        init_expr,
        EXPR_RECORD_STRIDE,
        EXPR_RECORD_FORM,
        HIR_EXPR_NONE);
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_INT;
    return TY_UNKNOWN;
}

uint local_decl_type(uint decl_token)
{
    uint ty = visible_type_for_token(decl_token);
    if (ty == TY_UNKNOWN)
        ty = local_decl_initializer_type(decl_token);
    return ty == TY_UNKNOWN ? TY_INT : ty;
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
    uint shift = (byte_i - 1u) * 8u;
    return (bits >> shift) & 0xffu;
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

uint memarg_len(uint offset)
{
    return 1u + u32_leb_len(2u) + u32_leb_len(offset);
}

uint memarg_load_byte(uint op, uint offset, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return u32_leb_byte(offset, byte_i - 2u);
}

uint align4(uint value)
{
    return (value + 3u) & ~3u;
}

uint aggregate_data_base()
{
    return align4((gParams.n_tokens + 1u) * 4u + gParams.source_len);
}

uint agg_local_base_slots(uint decl_token)
{
    return global_exclusive_prefix(
        decl_token,
        WG_SIZE,
        wasm_agg_local_base_by_token,
        wasm_agg_local_block_prefix);
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
    {
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;
    }

    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;
    }

    uint ty = call_param_row_type[row];
    if (ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal))
        return TY_ARRAY_BASE;
    return ty;
}

bool aggregate_address_expr_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    uint local_index = INVALID;
    bool is_param = function_param_local_index(decl_token, owner_fn, local_index);
    if (!is_param && valid_token(owner_fn))
    {
        uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
        if (ordinal != INVALID)
        {
            local_index = function_param_abi_ordinal(owner_fn, ordinal);
            is_param = true;
        }
    }
    if (is_param)
    {
        uint decl_ty = visible_type_for_token(decl_token);
        uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
        uint param_ty = call_param_type_value(owner_fn, ordinal);
        if (decl_ty != TY_UNKNOWN &&
            decl_ty < TY_ARRAY_BASE &&
            param_ty < TY_ARRAY_BASE &&
            method_decl_param_offset[owner_fn] != decl_token)
        {
            return false;
        }
        len = 1u + u32_leb_len(local_index);
        return true;
    }

    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        len = 1u + i32_sleb_len(base_address);
        return true;
    }

    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE)
    {
        if (!function_non_param_local_index(decl_token, owner_fn, local_index))
            return false;
        len = 1u + u32_leb_len(local_index);
        return true;
    }

    return false;
}

uint aggregate_address_expr_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return 0u;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return 0u;

    uint owner_fn = node_enclosing_fn_token(node);
    uint local_index = INVALID;
    if (function_param_local_index(decl_token, owner_fn, local_index))
        return local_get_byte(local_index, byte_i);

    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        return i32_const_byte(base_address, byte_i);
    }

    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE)
    {
        if (!function_non_param_local_index(decl_token, owner_fn, local_index))
            return 0u;
        return local_get_byte(local_index, byte_i);
    }

    return 0u;
}

uint aggregate_member_field_index(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return INVALID;
    uint member_name = hir_member_name_token[node];
    if (!valid_token(member_name))
        return INVALID;
    return member_result_field_index[member_name];
}

uint aggregate_member_field_type(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return TY_UNKNOWN;
    uint member_name = hir_member_name_token[node];
    if (!valid_token(member_name))
        return TY_UNKNOWN;
    uint member_type = visible_type_for_token(member_name);
    if (member_type != TY_UNKNOWN)
        return member_type;
    uint field_node = member_result_field_node[member_name];
    if (!valid_node(field_node))
        return TY_UNKNOWN;
    return visible_type_for_token(hir_token_pos[field_node]);
}

uint aggregate_member_len(uint node)
{
    node = resolve_expr_node(node);
    uint field_index = aggregate_member_field_index(node);
    if (field_index == INVALID)
        return 0u;
    uint address_len = 0u;
    if (!aggregate_address_expr_len(hir_member_receiver_node[node], address_len))
        return 0u;
    return address_len + memarg_len(field_index * 4u);
}

uint aggregate_member_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint field_index = aggregate_member_field_index(node);
    if (field_index == INVALID)
        return 0u;

    uint address_len = 0u;
    uint receiver = hir_member_receiver_node[node];
    if (!aggregate_address_expr_len(receiver, address_len))
        return 0u;
    if (byte_i < address_len)
        return aggregate_address_expr_byte(receiver, byte_i);

    uint op = aggregate_member_field_type(node) == TY_FLOAT ? WASM_F32_LOAD : WASM_I32_LOAD;
    return memarg_load_byte(op, field_index * 4u, byte_i - address_len);
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

    uint encoded_fn = enclosing_fn[decl_token];
    if (encoded_fn == 0u || encoded_fn - 1u != owner_fn ||
        !function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        return false;
    }
    decl_token = local_index;
    return true;
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

bool expr_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_FLOAT)
        return true;
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN)) == TY_FLOAT;
    return false;
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
    if (form == HIR_EXPR_FLOAT)
        return 5u;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return 2u;
    return 0u;
}

uint direct_call_arg_len(uint node)
{
    uint expr_len = direct_call_arg_expr_len(node);
    if (expr_len != 0u)
        return expr_len;

    uint value = 0u;
    return direct_call_arg_const_value(node, value) ? 1u + i32_sleb_len(value) : 0u;
}

uint direct_call_arg_abi_len(uint node, uint param_ty)
{
    if (param_ty >= TY_ARRAY_BASE)
    {
        uint len = 0u;
        return aggregate_address_expr_len(node, len) ? len : 0u;
    }
    return direct_call_arg_len(node);
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
    if (form == HIR_EXPR_FLOAT)
        return f32_const_byte(hir_expr_float_bits[node], byte_i);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
    return 0u;
}

uint direct_call_arg_byte(uint node, uint byte_i)
{
    uint expr_len = direct_call_arg_expr_len(node);
    if (expr_len != 0u)
        return direct_call_arg_expr_byte(node, byte_i);

    uint value = 0u;
    if (!direct_call_arg_const_value(node, value))
        return 0u;
    return i32_const_byte(value, byte_i);
}

uint direct_call_arg_abi_byte(uint node, uint param_ty, uint byte_i)
{
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_byte(node, byte_i);
    return direct_call_arg_byte(node, byte_i);
}

uint direct_call_expr_byte_from_record(
    uint wasm_func_index,
    uint call_expr_len,
    uint byte_i)
{
    if (wasm_func_index == INVALID)
        return 0u;

    // Argument records are compacted independently and scattered by the
    // argument passes. Position the call tail from the finalized fragment
    // length so nested/aggregate argument compaction cannot leave it at the
    // old conservative offset.
    uint tail_len = 1u + wasm_call_index_len(wasm_func_index);
    uint call_i = call_expr_len >= tail_len ? call_expr_len - tail_len : 0u;
    if (byte_i < call_i)
        return 0u;
    if (byte_i == call_i)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - call_i - 1u);
}

bool direct_call_arg_expr_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return false;
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return aggregate_member_field_type(node) == TY_FLOAT;
    return expr_atom_is_f32(node);
}

bool direct_call_arg_expr_neg_is_f32(uint node)
{
    node = resolve_expr_node(node);
    return node != INVALID &&
           expr_form(node) == HIR_EXPR_NEG &&
           direct_call_arg_expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
}

bool direct_call_arg_expr_operand_is_f32(uint node)
{
    return direct_call_arg_expr_atom_is_f32(node) || direct_call_arg_expr_neg_is_f32(node);
}

uint direct_call_arg_expr_binary_op_byte_for_node(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return 0u;

    uint form = expr_form(node);
    if (direct_call_arg_expr_operand_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ||
        direct_call_arg_expr_operand_is_f32(expr_record_slot(node, EXPR_RECORD_RIGHT)))
    {
        if (form == HIR_EXPR_EQ) return WASM_F32_EQ;
        if (form == HIR_EXPR_NE) return WASM_F32_NE;
        if (form == HIR_EXPR_LT) return WASM_F32_LT;
        if (form == HIR_EXPR_GT) return WASM_F32_GT;
        if (form == HIR_EXPR_LE) return WASM_F32_LE;
        if (form == HIR_EXPR_GE) return WASM_F32_GE;
        if (form == HIR_EXPR_ADD) return WASM_F32_ADD;
        if (form == HIR_EXPR_SUB) return WASM_F32_SUB;
        if (form == HIR_EXPR_MUL) return WASM_F32_MUL;
        if (form == HIR_EXPR_DIV) return WASM_F32_DIV;
        return 0u;
    }
    return expr_binary_op_byte(form);
}

uint direct_call_arg_expr_atom_len(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return 0u;
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return aggregate_member_len(node);
    return expr_non_call_atom_len(node);
}

uint direct_call_arg_expr_atom_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return aggregate_member_byte(node, byte_i);
    return expr_non_call_atom_byte(node, byte_i);
}

uint direct_call_arg_expr_len(uint root_node)
{
    root_node = resolve_expr_node(root_node);
    if (root_node == INVALID)
        return 0u;

    uint atom_len = direct_call_arg_expr_atom_len(root_node);
    if (atom_len != 0u)
        return atom_len;

    uint form = expr_form(root_node);
    if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
    {
        uint inner_len = direct_call_arg_expr_atom_len(expr_record_slot(root_node, EXPR_RECORD_LEFT));
        if (inner_len == 0u)
            return 0u;
        return inner_len + (form == HIR_EXPR_NOT ? 1u : (direct_call_arg_expr_neg_is_f32(root_node) ? 1u : 3u));
    }

    if (direct_call_arg_expr_binary_op_byte_for_node(root_node) == 0u)
        return 0u;
    uint left_len = direct_call_arg_expr_atom_len(expr_record_slot(root_node, EXPR_RECORD_LEFT));
    uint right_len = direct_call_arg_expr_atom_len(expr_record_slot(root_node, EXPR_RECORD_RIGHT));
    return left_len == 0u || right_len == 0u ? 0u : left_len + right_len + 1u;
}

uint direct_call_arg_expr_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return 0u;

    uint atom_len = direct_call_arg_expr_atom_len(node);
    if (atom_len != 0u)
        return direct_call_arg_expr_atom_byte(node, byte_i);

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
    {
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = direct_call_arg_expr_atom_len(inner);
        if (byte_i < inner_len)
            return direct_call_arg_expr_atom_byte(inner, byte_i);
        return byte_i == inner_len ? WASM_I32_EQZ : 0u;
    }
    if (form == HIR_EXPR_NEG)
    {
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = direct_call_arg_expr_atom_len(inner);
        if (direct_call_arg_expr_neg_is_f32(node))
        {
            if (byte_i < inner_len)
                return direct_call_arg_expr_atom_byte(inner, byte_i);
            return byte_i == inner_len ? WASM_F32_NEG : 0u;
        }
        if (byte_i < 2u)
            return i32_const_byte(0u, byte_i);
        if (byte_i < 2u + inner_len)
            return direct_call_arg_expr_atom_byte(inner, byte_i - 2u);
        return byte_i == 2u + inner_len ? WASM_I32_SUB : 0u;
    }

    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint left_len = direct_call_arg_expr_atom_len(left);
    uint right_len = direct_call_arg_expr_atom_len(right);
    if (byte_i < left_len)
        return direct_call_arg_expr_atom_byte(left, byte_i);
    if (byte_i < left_len + right_len)
        return direct_call_arg_expr_atom_byte(right, byte_i - left_len);
    return byte_i == left_len + right_len ? direct_call_arg_expr_binary_op_byte_for_node(node) : 0u;
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

uint let_direct_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint decl_token,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    uint set_len = 1u + u32_leb_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i < call_len)
        return direct_call_expr_byte_from_record(aux.x, call_len, byte_i);
    return local_set_byte(local_index, byte_i - call_len);
}

uint print_direct_call_i64_fragment_byte(
    uint call_node,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    uint call_len = fragment_len > 3u ? fragment_len - 3u : 0u;
    if (byte_i < call_len)
        return direct_call_expr_byte_from_record(aux.x, call_len, byte_i);
    if (byte_i == call_len)
        return WASM_I64_EXTEND_I32_S;
    if (byte_i == call_len + 1u)
        return WASM_CALL;
    return WASM_PRINT_I64_FUNC_INDEX;
}

uint return_direct_call_i32_fragment_byte(
    uint call_node,
    uint4 aux,
    uint nested_wasm_func_index,
    uint nested_fn_token,
    uint fragment_len,
    uint byte_i)
{
    uint call_len = fragment_len > 0u ? fragment_len - 1u : 0u;
    if (byte_i < call_len)
        return direct_call_expr_byte_from_record(aux.x, call_len, byte_i);
    return WASM_RETURN;
}

uint assign_direct_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint4 aux,
    uint fragment_len,
    uint byte_i)
{
    return let_direct_call_i32_fragment_byte(local_index, call_node, INVALID, aux, fragment_len, byte_i);
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
        return direct_call_expr_byte_from_record(aux.x, call_len, byte_i - call_start);

    uint op_i = call_start + call_len;
    if (byte_i == op_i)
        return assign_op_byte(op);

    return local_set_byte(local_index, byte_i - op_i - 1u);
}

bool scatter_handles_kind(uint kind)
{
    return kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64;
}

uint fragment_byte(uint4 meta, uint4 aux, uint fragment_len, uint byte_i)
{
    uint kind = meta.x;
    uint value = meta.y;

    if (kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32)
        return return_direct_call_i32_fragment_byte(value, aux, meta.z, meta.w, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32)
        return let_direct_call_i32_fragment_byte(meta.y, meta.z, meta.w, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32)
        return assign_direct_call_i32_fragment_byte(meta.y, meta.z, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
        return assign_compound_direct_call_i32_fragment_byte(meta.y, meta.z, meta.w, aux, fragment_len, byte_i);
    if (kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64)
        return print_direct_call_i64_fragment_byte(value, aux, fragment_len, byte_i);

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
    uint byte_i = body_byte_i - offset;
    if (byte_i >= len)
        return;

    uint4 meta = body_fragment_meta[token_i];
    if (!scatter_handles_kind(meta.x))
        return;
    uint4 aux = body_fragment_aux[token_i];
    body_words[offset + byte_i] = fragment_byte(meta, aux, len, byte_i);
}
