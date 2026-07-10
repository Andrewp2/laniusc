// Scatter simple scalar if fragments into the WASM body byte stream.

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
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_nearest_enclosing_control_node;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_IF_OPEN_I32 = 16u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_IF = 0x04u;
static const uint WASM_ELSE = 0x05u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
static const uint WASM_END = 0x0bu;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
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
static const uint WASM_F32_CONST = 0x43u;
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
static const uint TY_UNKNOWN = 0u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
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
static const uint HIR_MEMBER_EXPR = 21u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WG_SIZE = 256u;
static const uint MAX_EXPR_EMIT_STACK = 16u;
static const uint MAX_EXPR_EMIT_STEPS = 48u;
static const uint MAX_CONTROL_BRANCH_DEPTH = 16u;
static const uint CONDITION_MEMBER_FIELD_MASK = 0x00ffffffu;
static const uint CONDITION_MEMBER_FORM_MASK = 0x7fu;
static const uint CONDITION_MEMBER_FORM_SHIFT = 24u;
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

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint f32_const_byte(uint bits, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_F32_CONST;
    uint shift = (byte_i - 1u) * 8u;
    return (bits >> shift) & 0xffu;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gScan.n_items;
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
    uint form = expr_form(init_expr);
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return 3u;
    return TY_UNKNOWN;
}

uint local_decl_type(uint decl_token)
{
    uint ty = visible_type_for_token(decl_token);
    if (ty == TY_UNKNOWN)
        ty = local_decl_initializer_type(decl_token);
    return ty == TY_UNKNOWN ? 3u : ty;
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
        return method_receiver_param(fn_token, ordinal) ? 128u : TY_UNKNOWN;
    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? 128u : TY_UNKNOWN;
    }
    uint ty = call_param_row_type[row];
    return ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal) ? 128u : ty;
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
    return local_index != INVALID;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint param_count = function_param_abi_count(fn_token);
    uint local_max = wasm_func_local_max_by_token[fn_token];
    uint local_count = local_max == INVALID ? 0u : local_max + 1u;
    local_index = param_count + decl_token;
    if (local_decl_type(decl_token) == TY_FLOAT)
        local_index += local_count * 2u;
    return true;
}

bool local_decl_token_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
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
        if (!valid_node(control))
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

bool aggregate_address_expr_and_len(uint node, out uint len)
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
    if (function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        len = 1u + u32_leb_len(local_index);
        return true;
    }
    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        len = 1u + i32_sleb_len(address);
        return true;
    }
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE &&
        function_non_param_local_index(decl_token, owner_fn, local_index))
    {
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
            return 0u;
        }
        return local_get_byte(local_index, byte_i);
    }
    if (function_non_param_local_index(decl_token, owner_fn, local_index))
        return local_get_byte(local_index, byte_i);
    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        return i32_const_byte(address, byte_i);
    }
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE &&
        function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        return local_get_byte(local_index, byte_i);
    }
    return 0u;
}

uint member_expr_node_from_expr(uint node)
{
    for (uint depth = 0u; depth < MAX_EXPR_EMIT_STACK; depth += 1u)
    {
        if (!valid_node(node))
            return INVALID;
        uint member_name = hir_member_name_token[node];
        if (valid_token(member_name) && member_result_field_index[member_name] != INVALID)
            return node;
        if (expr_form(node) == HIR_EXPR_FORWARD)
        {
            uint forwarded = expr_record_slot(node, EXPR_RECORD_LEFT);
            if (valid_node(forwarded) && forwarded != node)
            {
                node = forwarded;
                continue;
            }
        }
        uint root = hir_expr_result_root_node[node];
        if (!valid_node(root) || root == node)
            return INVALID;
        node = root;
    }
    return INVALID;
}

uint aggregate_member_field_index(uint node)
{
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return INVALID;
    return member_result_field_index[hir_member_name_token[node]];
}

uint aggregate_member_field_type(uint node)
{
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;
    uint member_name = hir_member_name_token[node];
    uint ty = visible_type_for_token(member_name);
    if (ty != TY_UNKNOWN)
        return ty;
    uint field_node = member_result_field_node[member_name];
    return valid_node(field_node) ? visible_type_for_token(hir_token_pos[field_node]) : TY_UNKNOWN;
}

uint aggregate_member_len(uint node)
{
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return 0u;
    uint field_index = member_result_field_index[hir_member_name_token[node]];
    uint receiver_len = 0u;
    if (!aggregate_address_expr_and_len(hir_member_receiver_node[node], receiver_len))
        return 0u;
    return receiver_len + 2u + u32_leb_len(field_index * 4u);
}

uint memarg_load_byte(uint op, uint offset, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return u32_leb_byte(offset, byte_i - 2u);
}

uint memarg_len(uint offset)
{
    return 2u + u32_leb_len(offset);
}

uint aggregate_member_byte(uint node, uint byte_i)
{
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return 0u;
    uint field_index = member_result_field_index[hir_member_name_token[node]];
    uint receiver = hir_member_receiver_node[node];
    uint receiver_len = 0u;
    if (!aggregate_address_expr_and_len(receiver, receiver_len))
        return 0u;
    if (byte_i < receiver_len)
        return aggregate_address_expr_byte(receiver, byte_i);
    uint op = aggregate_member_field_type(node) == TY_FLOAT ? WASM_F32_LOAD : WASM_I32_LOAD;
    return memarg_load_byte(op, field_index * 4u, byte_i - receiver_len);
}

uint condition_member_len(uint local_index, uint packed_field)
{
    if (local_index == INVALID || packed_field == INVALID)
        return 0u;
    uint field_index = packed_field & CONDITION_MEMBER_FIELD_MASK;
    return 1u + u32_leb_len(local_index) + memarg_len(field_index * 4u);
}

uint condition_member_byte(uint local_index, uint packed_field, uint byte_i)
{
    uint local_len = 1u + u32_leb_len(local_index);
    if (byte_i < local_len)
        return local_get_byte(local_index, byte_i);
    uint field_index = packed_field & CONDITION_MEMBER_FIELD_MASK;
    uint op = (packed_field & 0x80000000u) != 0u ? WASM_F32_LOAD : WASM_I32_LOAD;
    return memarg_load_byte(op, field_index * 4u, byte_i - local_len);
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
    if (aggregate_member_field_index(node) != INVALID)
        return aggregate_member_field_type(node) == TY_FLOAT;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint form = expr_form(node);
    if (form == HIR_EXPR_FLOAT)
        return true;
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN)) == TY_FLOAT;
    return false;
}

bool expr_neg_is_f32(uint node)
{
    node = resolve_expr_node(node);
    return valid_node(node) &&
           expr_form(node) == HIR_EXPR_NEG &&
           expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
}

bool expr_operand_is_f32(uint node)
{
    return expr_atom_is_f32(node) || expr_neg_is_f32(node);
}

uint expr_binary_op_byte_for_node(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;

    uint form = expr_form(node);
    if (expr_operand_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ||
        expr_operand_is_f32(expr_record_slot(node, EXPR_RECORD_RIGHT)))
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

uint expr_non_call_atom_len(uint node)
{
    uint member_len = aggregate_member_len(node);
    if (member_len != 0u)
        return member_len;
    node = resolve_expr_node(node);
    if (!valid_node(node))
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

uint expr_simple_len(uint root_node)
{
    root_node = resolve_expr_node(root_node);
    if (!valid_node(root_node))
        return 0u;

    uint nodes[MAX_EXPR_EMIT_STACK];
    uint states[MAX_EXPR_EMIT_STACK];
    uint lens[MAX_EXPR_EMIT_STACK];
    uint sp = 1u;
    uint lsp = 0u;
    nodes[0u] = root_node;
    states[0u] = 0u;

    for (uint step = 0u; step < MAX_EXPR_EMIT_STEPS; step += 1u)
    {
        if (sp == 0u)
            break;

        uint node = nodes[sp - 1u];
        if (aggregate_member_len(node) == 0u)
            node = resolve_expr_node(node);
        if (!valid_node(node))
            return 0u;
        nodes[sp - 1u] = node;
        uint state = states[sp - 1u];
        uint atom_len = expr_non_call_atom_len(node);
        if (state == 0u && atom_len != 0u)
        {
            if (lsp >= MAX_EXPR_EMIT_STACK)
                return 0u;
            lens[lsp] = atom_len;
            lsp += 1u;
            sp -= 1u;
            continue;
        }

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (state == 0u)
            {
                if (sp >= MAX_EXPR_EMIT_STACK)
                    return 0u;
                states[sp - 1u] = 1u;
                nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
                states[sp] = 0u;
                sp += 1u;
                continue;
            }
            if (lsp < 1u)
                return 0u;
            lens[lsp - 1u] += form == HIR_EXPR_NOT ? 1u : (expr_neg_is_f32(node) ? 1u : 3u);
            sp -= 1u;
            continue;
        }

        if (expr_binary_op_byte_for_node(node) == 0u)
            return 0u;
        if (state == 0u)
        {
            if (sp >= MAX_EXPR_EMIT_STACK)
                return 0u;
            states[sp - 1u] = 1u;
            nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
            states[sp] = 0u;
            sp += 1u;
            continue;
        }
        if (state == 1u)
        {
            if (sp >= MAX_EXPR_EMIT_STACK)
                return 0u;
            states[sp - 1u] = 2u;
            nodes[sp] = expr_record_slot(node, EXPR_RECORD_RIGHT);
            states[sp] = 0u;
            sp += 1u;
            continue;
        }
        if (lsp < 2u)
            return 0u;
        uint right_len = lens[lsp - 1u];
        uint left_len = lens[lsp - 2u];
        lsp -= 1u;
        lens[lsp - 1u] = left_len + right_len + 1u;
        sp -= 1u;
    }

    return sp == 0u && lsp == 1u ? lens[0u] : 0u;
}

uint expr_non_call_atom_byte(uint node, uint byte_i)
{
    if (aggregate_member_len(node) != 0u)
        return aggregate_member_byte(node, byte_i);
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

uint expr_simple_byte(uint node, uint byte_i)
{
    for (uint step = 0u; step < MAX_EXPR_EMIT_STEPS; step += 1u)
    {
        if (aggregate_member_len(node) == 0u)
            node = resolve_expr_node(node);
        if (!valid_node(node))
            return 0u;

        uint atom_len = expr_non_call_atom_len(node);
        if (atom_len != 0u)
            return expr_non_call_atom_byte(node, byte_i);

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT)
        {
            uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
            uint inner_len = expr_simple_len(inner);
            if (byte_i < inner_len)
            {
                node = inner;
                continue;
            }
            return byte_i == inner_len ? WASM_I32_EQZ : 0u;
        }
        if (form == HIR_EXPR_NEG)
        {
            uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
            uint inner_len = expr_simple_len(inner);
            if (expr_neg_is_f32(node))
            {
                if (byte_i < inner_len)
                {
                    node = inner;
                    continue;
                }
                return byte_i == inner_len ? WASM_F32_NEG : 0u;
            }
            if (byte_i < 2u)
                return i32_const_byte(0u, byte_i);
            if (byte_i < 2u + inner_len)
            {
                node = inner;
                byte_i -= 2u;
                continue;
            }
            return byte_i == 2u + inner_len ? WASM_I32_SUB : 0u;
        }

        uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
        uint left_len = expr_simple_len(left);
        uint right_len = expr_simple_len(right);
        if (byte_i < left_len)
        {
            node = left;
            continue;
        }
        if (byte_i < left_len + right_len)
        {
            node = right;
            byte_i -= left_len;
            continue;
        }
        return byte_i == left_len + right_len ? expr_binary_op_byte_for_node(node) : 0u;
    }
    return 0u;
}

uint if_open_i32_fragment_byte(uint condition_node, uint4 aux, uint byte_i)
{
    uint root = condition_node;
    bool has_left_member = aux.x != INVALID && aux.y != INVALID;
    bool has_right_member = aux.z != INVALID && aux.w != INVALID;
    uint packed_member = has_left_member ? aux.y : aux.w;
    uint form = (packed_member >> CONDITION_MEMBER_FORM_SHIFT) & CONDITION_MEMBER_FORM_MASK;
    if (form == HIR_EXPR_NONE)
    {
        root = resolve_expr_node(condition_node);
        form = valid_node(root) ? expr_form(root) : HIR_EXPR_NONE;
    }
    if ((has_left_member || has_right_member) && expr_binary_op_byte(form) != 0u)
    {
        uint left = expr_record_slot(root, EXPR_RECORD_LEFT);
        uint right = expr_record_slot(root, EXPR_RECORD_RIGHT);
        uint left_len = has_left_member
                            ? condition_member_len(aux.x, aux.y)
                            : expr_simple_len(left);
        uint right_len = has_right_member
                             ? condition_member_len(aux.z, aux.w)
                             : expr_simple_len(right);
        if (byte_i < left_len)
            return has_left_member
                       ? condition_member_byte(aux.x, aux.y, byte_i)
                       : expr_simple_byte(left, byte_i);
        if (byte_i < left_len + right_len)
        {
            uint right_byte_i = byte_i - left_len;
            return has_right_member
                       ? condition_member_byte(aux.z, aux.w, right_byte_i)
                       : expr_simple_byte(right, right_byte_i);
        }
        uint op_i = left_len + right_len;
        if (byte_i == op_i)
        {
            bool uses_f32 =
                (has_left_member && (aux.y & 0x80000000u) != 0u) ||
                (has_right_member && (aux.w & 0x80000000u) != 0u) ||
                (!has_left_member && expr_operand_is_f32(left)) ||
                (!has_right_member && expr_operand_is_f32(right));
            if (uses_f32)
            {
                if (form == HIR_EXPR_EQ) return WASM_F32_EQ;
                if (form == HIR_EXPR_NE) return WASM_F32_NE;
                if (form == HIR_EXPR_LT) return WASM_F32_LT;
                if (form == HIR_EXPR_GT) return WASM_F32_GT;
                if (form == HIR_EXPR_LE) return WASM_F32_LE;
                if (form == HIR_EXPR_GE) return WASM_F32_GE;
            }
            return expr_binary_op_byte(form);
        }
        if (byte_i == op_i + 1u)
            return WASM_IF;
        return WASM_BLOCK_TYPE_EMPTY;
    }

    uint condition_len = expr_simple_len(condition_node);
    if (byte_i < condition_len)
        return expr_simple_byte(condition_node, byte_i);
    if (byte_i == condition_len)
        return WASM_IF;
    return WASM_BLOCK_TYPE_EMPTY;
}

bool scatter_if_simple_handles_kind(uint kind)
{
    return kind == BODY_FRAGMENT_IF_OPEN_I32 ||
           kind == BODY_FRAGMENT_IF_ELSE ||
           kind == BODY_FRAGMENT_IF_END;
}

uint if_simple_fragment_byte(uint4 meta, uint4 aux, uint byte_i)
{
    if (meta.x == BODY_FRAGMENT_IF_OPEN_I32)
        return if_open_i32_fragment_byte(meta.y, aux, byte_i);
    if (meta.x == BODY_FRAGMENT_IF_ELSE)
        return WASM_ELSE;
    if (meta.x == BODY_FRAGMENT_IF_END)
        return WASM_END;
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
    uint4 aux = body_fragment_aux[token_i];
    if (!scatter_if_simple_handles_kind(meta.x))
        return;
    body_words[offset + byte_i] = if_simple_fragment_byte(meta, aux, byte_i);
}
