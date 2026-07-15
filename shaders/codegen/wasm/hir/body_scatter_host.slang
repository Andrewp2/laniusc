// Scatter host-call WASM body fragments into the body byte stream.

import gpu_index;
import prefix_scan;
import call_relocation;
import expr_span_lookup;
import expr_emission_common;

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
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint2> expr_node_emission;
StructuredBuffer<uint2> expr_subtree_total;
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
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
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
static const uint BODY_FRAGMENT_HOST_CALL_VOID = 38u;
static const uint WASM_PROCESS_ARGC_FUNC_INDEX = 2u;
static const uint WASM_PROCESS_ARG_LEN_FUNC_INDEX = 3u;
static const uint WASM_PROCESS_ARG_READ_FUNC_INDEX = 4u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
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
static const uint MAX_PATH_SEGMENTS = 9u;
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

uint active_path_count()
{
    return min(path_count_out[0u], gParams.n_hir_nodes);
}

bool valid_path(uint path_i)
{
    return path_i != INVALID && path_i < active_path_count();
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
    local_index = 0u;
    for (uint i = 0u; i < ordinal; i += 1u)
        local_index += call_param_type_value(fn_token, i) == TY_STRING ? 2u : 1u;
    return true;
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

bool function_decl_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    if (function_param_local_index(decl_token, fn_token, local_index))
        return true;
    return function_non_param_local_index(decl_token, fn_token, local_index);
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

    if (local_decl_type(decl_token) != TY_STRING)
        return false;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    uint local_count = local_max == INVALID ? 0u : local_max + 1u;
    local_index = function_param_abi_count(fn_token) + local_count + decl_token;
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
        return 2u;
    uint i32_count = local_count * 2u;
    uint i32_count_len = u32_leb_len(i32_count);
    if (byte_i <= i32_count_len)
        return u32_leb_byte(i32_count, byte_i - 1u);
    if (byte_i == i32_count_len + 1u)
        return WASM_VALTYPE_I32;
    uint second_count_start = i32_count_len + 2u;
    uint f32_count_len = u32_leb_len(local_count);
    if (byte_i < second_count_start + f32_count_len)
        return u32_leb_byte(local_count, byte_i - second_count_start);
    return WASM_VALTYPE_F32;
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

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
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
            local_index = 0u;
            for (uint i = 0u; i < ordinal; i += 1u)
                local_index += call_param_type_value(owner_fn, i) == TY_STRING ? 2u : 1u;
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

uint path_node_for_callee(uint callee_node)
{
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

uint path_leaf_token_for_callee(uint callee_node)
{
    uint path_node = path_node_for_callee(callee_node);
    if (!valid_node(path_node))
        return INVALID;

    uint path_i = path_id_by_owner_hir[path_node];
    if (!valid_path(path_i))
        return INVALID;

    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;

    uint slot = path_segment_base[path_i] + count - 1u;
    if (slot >= gParams.n_tokens * MAX_PATH_SEGMENTS)
        return INVALID;

    uint token = path_segment_token[slot];
    return valid_token(token) ? token : INVALID;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint raw_callee_node = hir_call_callee_node[call_node];
    uint path_leaf = path_leaf_token_for_callee(raw_callee_node);
    if (valid_token(path_leaf))
        return path_leaf;

    uint callee_node = resolve_expr_node(raw_callee_node);
    if (!valid_node(callee_node))
        return INVALID;
    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        return valid_token(member_token) ? member_token : INVALID;
    }

    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_site_token(uint call_node)
{
    return valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
}

uint semantic_callee_token_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = call_site_token(call_node);
    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_metadata_token(uint call_node, uint callee_token)
{
    uint site_token = call_site_token(call_node);
    uint semantic_token = semantic_callee_token_for_call(call_node);

    if (valid_token(site_token) && call_dependency_decl[site_token] != INVALID)
        return site_token;
    if (valid_token(semantic_token) && call_dependency_decl[semantic_token] != INVALID)
        return semantic_token;
    if (valid_token(callee_token) && call_dependency_decl[callee_token] != INVALID)
        return callee_token;

    if (valid_token(site_token) && valid_token(call_fn_index[site_token]))
        return site_token;
    if (valid_token(semantic_token) && valid_token(call_fn_index[semantic_token]))
        return semantic_token;
    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token]))
        return callee_token;

    return callee_token;
}

uint call_fn_token_for_call(uint call_node)
{
    uint callee_token = call_callee_token(call_node);
    uint metadata_token = call_metadata_token(call_node, callee_token);
    if (!valid_token(metadata_token)) return INVALID;
    if (call_dependency_decl[metadata_token] != INVALID) return metadata_token;
    uint local_fn = call_fn_index[metadata_token];
    return valid_token(local_fn) ? local_fn : INVALID;
}

bool supported_call_target_token(uint token) { return supported_function_token(token) || (valid_token(token) && call_dependency_decl[token] != INVALID); }
uint wasm_call_target_for_call(uint call_node, uint fn_token) { uint token = call_metadata_token(call_node, call_callee_token(call_node)); return valid_token(token) && call_dependency_decl[token] != INVALID ? 0x80000000u | (call_dependency_decl[token] & 0x7fffffffu) : wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT; }

uint call_return_type_for_call(uint call_node, uint fn_token)
{
    uint callee_token = call_callee_token(call_node);
    uint metadata_token = call_metadata_token(call_node, callee_token);
    uint metadata_return_ty = valid_token(metadata_token) ? call_return_type[metadata_token] : TY_UNKNOWN;
    return metadata_return_ty != TY_UNKNOWN && metadata_return_ty != INVALID
               ? metadata_return_ty
               : call_return_type[fn_token];
}

bool type_is_i32_value(uint ty)
{
    return ty == TY_BOOL || ty == TY_INT || ty == TY_UINT;
}

bool type_is_i32_abi_value(uint ty)
{
    return type_is_i32_value(ty) || ty == TY_STRING || ty >= TY_ARRAY_BASE;
}

bool type_is_i32_abi_param(uint fn_token, uint ordinal, uint ty)
{
    return type_is_i32_abi_value(ty) || (ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal));
}

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
}

bool direct_user_call_node(
    uint call_node,
    out uint fn_token,
    out uint wasm_func_index,
    out uint arg_count)
{
    fn_token = INVALID;
    wasm_func_index = INVALID;
    arg_count = 0u;
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    uint metadata_token = call_metadata_token(call_node, callee_token);
    if (!valid_token(metadata_token) || call_intrinsic_tag[metadata_token] != 0u)
        return false;

    fn_token = call_fn_token_for_call(call_node);
    if (!supported_call_target_token(fn_token))
        return false;

    uint explicit_arg_count = hir_call_arg_count[call_node];
    bool has_receiver_arg = direct_call_record_has_receiver_arg(
        call_node,
        fn_token,
        explicit_arg_count + 1u);
    arg_count = explicit_arg_count + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    uint return_ty = call_return_type_for_call(call_node, fn_token);
    if (!type_is_i32_value(return_ty) && return_ty != TY_FLOAT)
        return false;

    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint param_ty = call_param_type_value(fn_token, i);
        if (!type_is_i32_abi_param(fn_token, i, param_ty) && param_ty != TY_FLOAT)
            return false;
    }

    wasm_func_index = wasm_call_target_for_call(call_node, fn_token);
    return true;
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

bool expr_binary_form_supported(uint form)
{
    return form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
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
    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_name = hir_member_name_token[node];
        return visible_type_for_token(member_name) == TY_FLOAT;
    }
    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint fn_token = call_fn_token_for_call(node);
        return call_return_type_for_call(node, fn_token) == TY_FLOAT;
    }
    return false;
}

bool expr_neg_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID || expr_form(node) != HIR_EXPR_NEG)
        return false;
    return expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
}

bool expr_operand_is_f32(uint node)
{
    return expr_atom_is_f32(node) || expr_neg_is_f32(node);
}

bool expr_binary_operands_are_f32(uint node)
{
    return expr_operand_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ||
           expr_operand_is_f32(expr_record_slot(node, EXPR_RECORD_RIGHT));
}

uint expr_binary_op_byte_for_node(uint node)
{
    node = resolve_expr_node(node);
    if (node == INVALID)
        return 0u;

    uint form = expr_form(node);
    if (expr_binary_operands_are_f32(node))
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
        if (!const_atom_value(expr_record_slot(node, EXPR_RECORD_LEFT), inner) &&
            !const_atom_value(expr_record_slot(node, EXPR_RECORD_RIGHT), inner))
        {
            return false;
        }
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
    uint expr_len = expr_no_call_len(node);
    if (expr_len != 0u)
        return expr_len;

    uint value = 0u;
    return direct_call_arg_const_value(node, value) ? 1u + i32_sleb_len(value) : 0u;
}

uint direct_call_arg_scalar_len(uint node)
{
    return expr_no_call_len(node);
}

uint direct_call_arg_abi_len(uint node, uint param_ty)
{
    if (param_ty == TY_STRING)
        return string_value_expr_len(node);
    if (param_ty >= TY_ARRAY_BASE)
    {
        uint len = 0u;
        return aggregate_address_expr_len(node, len) ? len : 0u;
    }
    return direct_call_arg_len(node);
}

uint direct_call_arg_scalar_abi_len(uint node, uint param_ty)
{
    if (param_ty == TY_STRING)
        return string_value_expr_len(node);
    if (param_ty >= TY_ARRAY_BASE)
    {
        uint len = 0u;
        return aggregate_address_expr_len(node, len) ? len : 0u;
    }
    return direct_call_arg_scalar_len(node);
}

uint expr_atom_len(uint node)
{
    return expr_non_call_atom_len(node);
}

uint expr_no_call_len(uint root_node)
{
    root_node = resolve_expr_node(root_node);
    if (!valid_node(root_node))
        return 0u;
    uint2 total = expr_subtree_total[root_node];
    return total.y == 0u ? total.x : 0u;
}

uint direct_call_expr_len(uint node)
{
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    if (!direct_user_call_node(node, fn_token, wasm_func_index, arg_count))
        return 0u;
    return direct_call_expr_len_from_record(node, wasm_func_index, arg_count, fn_token);
}

uint expr_simple_len(uint root_node)
{
    return expr_no_call_len(root_node);
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

uint scanned_expr_node_contribution_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;

    uint emission_byte = 0u;
    if (wasm_expr_emission_byte(expr_node_emission[node], byte_i, emission_byte))
        return emission_byte;

    uint atom_len = expr_non_call_atom_len(node);
    if (atom_len != 0u)
        return byte_i < atom_len ? expr_non_call_atom_byte(node, byte_i) : 0u;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
        return byte_i == 0u ? WASM_I32_EQZ : 0u;
    if (form == HIR_EXPR_NEG)
    {
        if (expr_neg_is_f32(node))
            return byte_i == 0u ? WASM_F32_NEG : 0u;
        if (byte_i < 2u)
            return i32_const_byte(0xffffffffu, byte_i);
        return byte_i == 2u ? WASM_I32_MUL : 0u;
    }
    return byte_i == 0u ? expr_binary_op_byte_for_node(node) : 0u;
}

uint scanned_expr_byte(uint root_node, uint byte_i)
{
    root_node = resolve_expr_node(root_node);
    if (!valid_node(root_node))
        return 0u;

    uint2 total = expr_subtree_total[root_node];
    uint span_start = 0u;
    uint span_len = 0u;
    if (total.y != 0u || total.x == 0u || byte_i >= total.x ||
        !wasm_expr_node_span(root_node, gParams.n_hir_nodes, span_start, span_len))
    {
        return 0u;
    }

    uint subtree_end = span_start + span_len;
    if (subtree_end < total.x)
        return 0u;

    uint owner_node = INVALID;
    uint owner_byte_i = 0u;
    if (!wasm_expr_span_byte_owner(
            root_node,
            gParams.n_hir_nodes,
            subtree_end - total.x + byte_i,
            owner_node,
            owner_byte_i))
    {
        return 0u;
    }
    return scanned_expr_node_contribution_byte(owner_node, owner_byte_i);
}

uint direct_call_arg_byte(uint node, uint byte_i)
{
    uint expr_len = expr_no_call_len(node);
    if (expr_len != 0u)
        return scanned_expr_byte(node, byte_i);

    uint value = 0u;
    if (!direct_call_arg_const_value(node, value))
        return 0u;
    return i32_const_byte(value, byte_i);
}

uint direct_call_arg_scalar_byte(uint node, uint byte_i)
{
    return scanned_expr_byte(node, byte_i);
}

uint direct_call_arg_abi_byte(uint node, uint param_ty, uint byte_i)
{
    if (param_ty == TY_STRING)
        return string_value_expr_byte(node, byte_i);
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_byte(node, byte_i);
    return direct_call_arg_byte(node, byte_i);
}

uint direct_call_arg_scalar_abi_byte(uint node, uint param_ty, uint byte_i)
{
    if (param_ty == TY_STRING)
        return string_value_expr_byte(node, byte_i);
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_byte(node, byte_i);
    return direct_call_arg_scalar_byte(node, byte_i);
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
    uint raw_len = 0u;
    if (string_literal_ptr_len(node, ptr, raw_len))
        return 1u + i32_sleb_len(ptr) + 1u + i32_sleb_len(raw_len);

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
        !function_decl_local_index(decl_token, owner_fn, ptr_local) ||
        !function_string_len_local_index(decl_token, owner_fn, len_local))
    {
        return 0u;
    }

    return local_get_len(ptr_local) + local_get_len(len_local);
}

uint string_value_expr_byte(uint node, uint byte_i)
{
    uint ptr = 0u;
    uint raw_len = 0u;
    if (string_literal_ptr_len(node, ptr, raw_len))
    {
        uint ptr_len = 1u + i32_sleb_len(ptr);
        if (byte_i < ptr_len)
            return i32_const_byte(ptr, byte_i);
        return i32_const_byte(raw_len, byte_i - ptr_len);
    }

    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return 0u;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint ptr_local = INVALID;
    uint len_local = INVALID;
    if (!function_decl_local_index(decl_token, owner_fn, ptr_local) ||
        !function_string_len_local_index(decl_token, owner_fn, len_local))
    {
        return 0u;
    }

    uint ptr_len = local_get_len(ptr_local);
    if (byte_i < ptr_len)
        return local_get_byte(ptr_local, byte_i);
    return local_get_byte(len_local, byte_i - ptr_len);
}

uint string_ptr_len_call_byte(uint string_node, uint wasm_func_index, uint byte_i)
{
    uint string_len = string_value_expr_len(string_node);
    if (string_len == 0u)
        return 0u;

    if (byte_i < string_len)
        return string_value_expr_byte(string_node, byte_i);
    uint call_start = string_len;
    if (byte_i == call_start)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - call_start - 1u);
}

uint handle_string_call_byte(uint call_node, uint wasm_func_index, uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    uint handle_node = direct_call_arg_node(call_node, 0u);
    uint handle_len = direct_call_arg_scalar_len(handle_node);
    if (byte_i < handle_len)
        return direct_call_arg_scalar_byte(handle_node, byte_i);

    uint string_node = direct_call_arg_node(call_node, 1u);
    uint string_len = string_value_expr_len(string_node);
    if (string_len == 0u)
        return 0u;

    uint string_start = handle_len;
    if (byte_i < string_start + string_len)
        return string_value_expr_byte(string_node, byte_i - string_start);
    uint call_start = string_start + string_len;
    if (byte_i == call_start)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - call_start - 1u);
}

uint direct_call_expr_byte_from_record(
    uint node,
    uint wasm_func_index,
    uint arg_count,
    uint fn_token,
    uint byte_i)
{
    node = resolve_expr_node(node);
    if (wasm_func_index == INVALID)
        return 0u;

    uint offset = 0u;
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_abi_arg_node(node, fn_token, arg_count, i);
        uint param_ty = call_param_type_value(fn_token, i);
        uint arg_len = direct_call_arg_abi_len(arg_node, param_ty);
        if (byte_i < offset + arg_len)
            return direct_call_arg_abi_byte(arg_node, param_ty, byte_i - offset);
        offset += arg_len;
    }

    if (byte_i == offset)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - offset - 1u);
}

uint direct_call_expr_scalar_byte_from_record(
    uint node,
    uint wasm_func_index,
    uint arg_count,
    uint fn_token,
    uint byte_i)
{
    node = resolve_expr_node(node);
    if (wasm_func_index == INVALID)
        return 0u;

    uint offset = 0u;
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_abi_arg_node(node, fn_token, arg_count, i);
        uint param_ty = call_param_type_value(fn_token, i);
        uint arg_len = direct_call_arg_scalar_abi_len(arg_node, param_ty);
        if (byte_i < offset + arg_len)
            return direct_call_arg_scalar_abi_byte(arg_node, param_ty, byte_i - offset);
        offset += arg_len;
    }

    if (byte_i == offset)
        return WASM_CALL;
    return wasm_call_index_byte(wasm_func_index, byte_i - offset - 1u);
}

uint direct_call_expr_len_from_record(
    uint node,
    uint wasm_func_index,
    uint arg_count,
    uint fn_token)
{
    node = resolve_expr_node(node);
    if (wasm_func_index == INVALID)
        return 0u;

    uint total = 1u + wasm_call_index_len(wasm_func_index);
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_len = direct_call_arg_abi_len(
            direct_call_abi_arg_node(node, fn_token, arg_count, i),
            call_param_type_value(fn_token, i));
        if (arg_len == 0u)
            return 0u;
        total += arg_len;
    }
    return total;
}

uint direct_call_expr_byte(uint node, uint byte_i)
{
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    if (!direct_user_call_node(node, fn_token, wasm_func_index, arg_count))
        return 0u;
    return direct_call_expr_byte_from_record(node, wasm_func_index, arg_count, fn_token, byte_i);
}

uint expr_atom_byte(uint node, uint byte_i)
{
    return expr_non_call_atom_byte(node, byte_i);
}

uint expr_no_call_byte(uint node, uint byte_i)
{
    return scanned_expr_byte(node, byte_i);
}

uint expr_simple_byte(uint node, uint byte_i)
{
    return scanned_expr_byte(node, byte_i);
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
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, aux.z, byte_i);
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
            INVALID,
            byte_i);
    return local_set_byte(local_index, byte_i - call_len);
}

uint let_host_string_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint wasm_func_index,
    uint mode,
    uint fragment_len,
    uint byte_i)
{
    uint set_len = 1u + u32_leb_len(local_index);
    uint call_len = fragment_len > set_len ? fragment_len - set_len : 0u;
    if (byte_i < call_len)
    {
        if (mode == HOST_STR_CALL_OPEN_READ_PATH || mode == HOST_STR_CALL_OPEN_WRITE_PATH)
        {
            call_node = resolve_expr_node(call_node);
            return string_ptr_len_call_byte(direct_call_arg_node(call_node, 0u), wasm_func_index, byte_i);
        }
        if (mode == HOST_STR_CALL_WRITE_TEXT)
            return handle_string_call_byte(call_node, wasm_func_index, byte_i);
    }
    return local_set_byte(local_index, byte_i - call_len);
}

uint return_host_call_i32_fragment_byte(
    uint call_node,
    uint wasm_func_index,
    uint arg_count,
    uint fragment_len,
    uint byte_i)
{
    uint call_len = fragment_len > 0u ? fragment_len - 1u : 0u;
    if (byte_i < call_len)
    {
        return direct_call_expr_scalar_byte_from_record(
            call_node,
            wasm_func_index,
            arg_count,
            INVALID,
            byte_i);
    }
    return WASM_RETURN;
}

uint return_host_string_call_i32_fragment_byte(
    uint call_node,
    uint wasm_func_index,
    uint mode,
    uint fragment_len,
    uint byte_i)
{
    uint call_len = fragment_len > 0u ? fragment_len - 1u : 0u;
    if (byte_i < call_len)
    {
        if (mode == HOST_STR_CALL_OPEN_READ_PATH || mode == HOST_STR_CALL_OPEN_WRITE_PATH)
        {
            call_node = resolve_expr_node(call_node);
            return string_ptr_len_call_byte(direct_call_arg_node(call_node, 0u), wasm_func_index, byte_i);
        }
        if (mode == HOST_STR_CALL_WRITE_TEXT)
            return handle_string_call_byte(call_node, wasm_func_index, byte_i);
    }
    return WASM_RETURN;
}

uint host_call_void_fragment_byte(
    uint call_node,
    uint wasm_func_index,
    uint arg_count,
    uint byte_i)
{
    return direct_call_expr_scalar_byte_from_record(
        call_node,
        wasm_func_index,
        arg_count,
        INVALID,
        byte_i);
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
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, aux.z, byte_i - call_start);

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
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, aux.z, byte_i);
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
        return direct_call_expr_scalar_byte_from_record(call_node, aux.x, aux.y, aux.z, byte_i);
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
    uint call_len = direct_call_expr_len_from_record(call_node, aux.x, aux.y, aux.z);

    if (call_side == 0u)
    {
        if (byte_i < call_len)
            return direct_call_expr_byte_from_record(call_node, aux.x, aux.y, aux.z, byte_i);
        if (byte_i < call_len + atom_len)
            return expr_atom_byte(atom_node, byte_i - call_len);
        if (byte_i == call_len + atom_len)
            return op;
        return WASM_RETURN;
    }

    if (byte_i < atom_len)
        return expr_atom_byte(atom_node, byte_i);
    if (byte_i < atom_len + call_len)
        return direct_call_expr_byte_from_record(call_node, aux.x, aux.y, aux.z, byte_i - atom_len);
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

bool scatter_handles_kind(uint kind)
{
    return kind == BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR ||
           kind == BODY_FRAGMENT_LET_HOST_NO_ARG_I32;
}

uint fragment_byte(uint4 meta, uint4 aux, uint fragment_len, uint byte_i)
{
    uint kind = meta.x;

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
