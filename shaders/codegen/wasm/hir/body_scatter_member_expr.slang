// Scatter aggregate-member expression fragments into the WASM body byte stream.

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
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> call_return_type;
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
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LET_EXPR_I32 = 9u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_I32 = 10u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 = 11u;
static const uint BODY_FRAGMENT_PRINT_EXPR_I64 = 12u;
static const uint BODY_FRAGMENT_RETURN_EXPR_I32 = 13u;
static const uint BODY_FRAGMENT_AGG_FIELD_STORE_I32 = 40u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint HIR_MEMBER_EXPR = 21u;
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
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_EXTEND_I32_S = 0xacu;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_RETURN = 0x0fu;
static const uint WASM_CALL = 0x10u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
static const uint WASM_I32_STORE = 0x36u;
static const uint WASM_F32_STORE = 0x38u;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I32_EQ = 0x46u;
static const uint WASM_I32_NE = 0x47u;
static const uint WASM_I32_LT_S = 0x48u;
static const uint WASM_I32_GT_S = 0x4au;
static const uint WASM_I32_LE_S = 0x4cu;
static const uint WASM_I32_GE_S = 0x4eu;
static const uint WASM_F32_EQ = 0x5bu;
static const uint WASM_F32_NE = 0x5cu;
static const uint WASM_F32_LT = 0x5du;
static const uint WASM_F32_GT = 0x5eu;
static const uint WASM_F32_LE = 0x5fu;
static const uint WASM_F32_GE = 0x60u;
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
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WASM_MAX_DIRECT_CALL_ARGS = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_EXPR_EMIT_STACK = 16u;
static const uint MAX_EXPR_EMIT_STEPS = 48u;
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

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
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
    return 2u + u32_leb_len(offset);
}

uint memarg_load_byte(uint op, uint offset, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return u32_leb_byte(offset, byte_i - 2u);
}

uint memarg_i32_byte(uint op, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return 0u;
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
    uint local_count = 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    if (local_max != INVALID)
        local_count = local_max + 1u;
    local_index = param_count + decl_token;
    if (local_decl_type(decl_token) == TY_FLOAT)
        local_index += local_count;
    return true;
}

bool local_decl_token_for_name_expr(uint node, out uint local_index)
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
            local_index = ordinal;
            is_param = true;
        }
    }
    if (is_param)
    {
        uint decl_ty = visible_type_for_token(decl_token);
        uint param_ty = call_param_type_value(owner_fn, local_index);
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

uint expr_semantic_type(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return TY_UNKNOWN;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = call_return_type[token];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

bool expr_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint form = expr_form(node);
    if (form == HIR_EXPR_FLOAT)
        return true;
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN)) == TY_FLOAT;
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return aggregate_member_field_type(node) == TY_FLOAT;
    return false;
}

bool expr_result_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint ty = expr_semantic_type(node);
    if (ty != TY_UNKNOWN)
        return ty == TY_FLOAT;
    if (expr_atom_is_f32(node))
        return true;
    uint form = expr_form(node);
    if (form == HIR_EXPR_NEG)
    {
        uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
        ty = expr_semantic_type(left);
        return ty == TY_FLOAT || (ty == TY_UNKNOWN && expr_atom_is_f32(left));
    }
    if (form == HIR_EXPR_ADD || form == HIR_EXPR_SUB || form == HIR_EXPR_MUL || form == HIR_EXPR_DIV)
    {
        uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
        uint left_ty = expr_semantic_type(left);
        uint right_ty = expr_semantic_type(right);
        return left_ty == TY_FLOAT ||
               right_ty == TY_FLOAT ||
               (left_ty == TY_UNKNOWN && expr_atom_is_f32(left)) ||
               (right_ty == TY_UNKNOWN && expr_atom_is_f32(right));
    }
    return false;
}

bool expr_neg_is_f32(uint node)
{
    node = resolve_expr_node(node);
    return valid_node(node) &&
           expr_form(node) == HIR_EXPR_NEG &&
           expr_result_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
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

uint expr_binary_op_byte_for_node(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;
    uint form = expr_form(node);
    if (expr_result_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ||
        expr_result_is_f32(expr_record_slot(node, EXPR_RECORD_RIGHT)))
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

uint expr_atom_len(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;
    uint member_len = aggregate_member_len(node);
    if (member_len != 0u)
        return member_len;
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
        return 1u + u32_leb_len(local_index);
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
    uint member_len = aggregate_member_len(node);
    if (member_len != 0u)
        return aggregate_member_byte(node, byte_i);
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
        return local_get_byte(local_index, byte_i);
    if (form == HIR_EXPR_INT)
        return i32_const_byte(hir_expr_int_value[node], byte_i);
    if (form == HIR_EXPR_FLOAT)
        return f32_const_byte(hir_expr_float_bits[node], byte_i);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
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

    uint step = 0u;
    while (step < MAX_EXPR_EMIT_STEPS)
    {
        if (sp == 0u)
            break;

        uint node = resolve_expr_node(nodes[sp - 1u]);
        if (!valid_node(node))
            return 0u;
        nodes[sp - 1u] = node;
        uint state = states[sp - 1u];
        uint atom_len = expr_atom_len(node);
        if (state == 0u && atom_len != 0u)
        {
            if (lsp >= MAX_EXPR_EMIT_STACK)
                return 0u;
            lens[lsp] = atom_len;
            lsp += 1u;
            sp -= 1u;
            step += 1u;
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
                step += 1u;
                continue;
            }
            if (lsp < 1u)
                return 0u;
            lens[lsp - 1u] += form == HIR_EXPR_NOT ? 1u : (expr_neg_is_f32(node) ? 1u : 3u);
            sp -= 1u;
            step += 1u;
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
            step += 1u;
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
            step += 1u;
            continue;
        }
        if (lsp < 2u)
            return 0u;
        uint right_len = lens[lsp - 1u];
        uint left_len = lens[lsp - 2u];
        lsp -= 1u;
        lens[lsp - 1u] = left_len + right_len + 1u;
        sp -= 1u;
        step += 1u;
    }

    return sp == 0u && lsp == 1u ? lens[0u] : 0u;
}

uint expr_simple_byte(uint node, uint byte_i)
{
    uint step = 0u;
    while (step < MAX_EXPR_EMIT_STEPS)
    {
        node = resolve_expr_node(node);
        if (!valid_node(node))
            return 0u;

        uint atom_len = expr_atom_len(node);
        if (atom_len != 0u)
            return expr_atom_byte(node, byte_i);

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT)
        {
            uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
            uint inner_len = expr_simple_len(inner);
            if (byte_i < inner_len)
            {
                node = inner;
                step += 1u;
                continue;
            }
            return byte_i == inner_len ? WASM_I32_EQZ : 0u;
        }
        if (form == HIR_EXPR_NEG)
        {
            if (expr_neg_is_f32(node))
            {
                uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
                uint inner_len = expr_simple_len(inner);
                if (byte_i < inner_len)
                {
                    node = inner;
                    step += 1u;
                    continue;
                }
                return byte_i == inner_len ? WASM_F32_NEG : 0u;
            }
            if (byte_i < 2u)
                return i32_const_byte(0u, byte_i);
            uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
            uint inner_len = expr_simple_len(inner);
            if (byte_i < 2u + inner_len)
            {
                node = inner;
                byte_i -= 2u;
                step += 1u;
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
            step += 1u;
            continue;
        }
        if (byte_i < left_len + right_len)
        {
            node = right;
            byte_i -= left_len;
            step += 1u;
            continue;
        }
        return byte_i == left_len + right_len ? expr_binary_op_byte_for_node(node) : 0u;
    }
    return 0u;
}

uint let_expr_i32_fragment_byte(uint local_index, uint expr_node, uint byte_i)
{
    uint expr_len = expr_simple_len(expr_node);
    if (byte_i < expr_len)
        return expr_simple_byte(expr_node, byte_i);
    return local_set_byte(local_index, byte_i - expr_len);
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
        return expr_binary_op_byte(op == 2u ? HIR_EXPR_ADD :
                                   op == 3u ? HIR_EXPR_SUB :
                                   op == 4u ? HIR_EXPR_MUL :
                                   op == 5u ? HIR_EXPR_DIV :
                                   HIR_EXPR_MOD);
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

uint aggregate_field_store_fragment_byte(uint address, uint expr_node, uint byte_i)
{
    uint address_len = 1u + i32_sleb_len(address);
    if (byte_i < address_len)
        return i32_const_byte(address, byte_i);

    uint expr_start = address_len;
    uint expr_len = expr_simple_len(expr_node);
    if (byte_i < expr_start + expr_len)
        return expr_simple_byte(expr_node, byte_i - expr_start);

    uint op = expr_result_is_f32(expr_node) ? WASM_F32_STORE : WASM_I32_STORE;
    return memarg_i32_byte(op, byte_i - expr_start - expr_len);
}

bool expr_contains_member(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint nodes[MAX_EXPR_EMIT_STACK];
    uint sp = 0u;
    nodes[sp] = node;
    sp += 1u;

    uint step = 0u;
    while (step < MAX_EXPR_EMIT_STEPS)
    {
        if (sp == 0u)
            return false;

        node = resolve_expr_node(nodes[sp - 1u]);
        sp -= 1u;
        if (!valid_node(node))
        {
            step += 1u;
            continue;
        }
        if (hir_kind[node] == HIR_MEMBER_EXPR)
            return aggregate_member_len(node) != 0u;

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (sp < MAX_EXPR_EMIT_STACK)
            {
                nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
                sp += 1u;
            }
            step += 1u;
            continue;
        }
        if (expr_binary_op_byte(form) != 0u)
        {
            if (sp + 2u <= MAX_EXPR_EMIT_STACK)
            {
                nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
                nodes[sp + 1u] = expr_record_slot(node, EXPR_RECORD_RIGHT);
                sp += 2u;
            }
        }
        step += 1u;
    }
    return false;
}

bool scatter_handles_fragment(uint4 meta)
{
    return (meta.x == BODY_FRAGMENT_LET_EXPR_I32 && expr_contains_member(meta.z)) ||
           meta.x == BODY_FRAGMENT_RETURN_EXPR_I32 ||
           meta.x == BODY_FRAGMENT_AGG_FIELD_STORE_I32;
}

uint fragment_byte(uint4 meta, uint byte_i)
{
    uint kind = meta.x;
    if (kind == BODY_FRAGMENT_LET_EXPR_I32)
        return let_expr_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_EXPR_I32)
        return return_expr_i32_fragment_byte(meta.y, byte_i);
    if (kind == BODY_FRAGMENT_AGG_FIELD_STORE_I32)
        return aggregate_field_store_fragment_byte(meta.y, meta.z, byte_i);
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
    uint guard = 0u;
    while (guard < 32u)
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
        guard += 1u;
    }
    uint token_i = lo;
    if (token_i >= gScan.n_items)
        return;
    uint len = body_fragment_len[token_i];
    uint offset = body_prefix_for_token(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len)
        return;

    uint4 meta = body_fragment_meta[token_i];
    if (!scatter_handles_fragment(meta))
        return;

    uint byte_i = body_byte_i - offset;
    body_words[offset + byte_i] = fragment_byte(meta, byte_i);
}
