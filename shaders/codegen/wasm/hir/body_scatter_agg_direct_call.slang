// Rewrite aggregate direct-call fragments with HIR-driven argument byte emission.

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
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 = 44u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint HIR_CALL_EXPR = 19u;
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
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
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
static const uint WG_SIZE = 256u;
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

uint arg_count_prefix_for_fragment(uint fragment_i)
{
    return global_exclusive_prefix(
        fragment_i,
        WG_SIZE,
        wasm_agg_call_arg_count_local_prefix,
        wasm_agg_call_arg_count_block_prefix);
}

uint arg_byte_prefix_for_record(uint record_i)
{
    return global_exclusive_prefix(
        record_i,
        WG_SIZE,
        wasm_agg_call_arg_byte_local_prefix,
        wasm_agg_call_arg_byte_block_prefix);
}

uint arg_bytes_for_fragment(uint fragment_i)
{
    uint count = wasm_agg_call_arg_count_by_fragment[fragment_i];
    if (count == 0u)
        return 0u;
    uint first_record = arg_count_prefix_for_fragment(fragment_i);
    uint last_record = first_record + count - 1u;
    return arg_byte_prefix_for_record(last_record) +
           wasm_agg_call_arg_len[last_record] -
           arg_byte_prefix_for_record(first_record);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
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

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
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
    uint param_count = function_param_abi_count(fn_token);
    local_index = param_count + decl_token;
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
    if (!valid_token(decl_token) || visible_type_for_token(decl_token) >= TY_ARRAY_BASE)
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
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;

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

    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE &&
        body_let_init_expr_by_decl_token[decl_token] != INVALID)
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

    uint field_node = member_result_field_node[member_name];
    if (valid_node(field_node))
    {
        uint field_type = visible_type_for_token(hir_token_pos[field_node]);
        if (field_type != TY_UNKNOWN)
            return field_type;
    }

    return visible_type_for_token(member_name);
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

bool expr_neg_is_f32(uint node)
{
    node = resolve_expr_node(node);
    return valid_node(node) &&
           expr_form(node) == HIR_EXPR_NEG &&
           expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
}

uint expr_binary_op_byte_for_node(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;
    uint form = expr_form(node);
    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    if (expr_atom_is_f32(left) || expr_atom_is_f32(right))
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

uint expr_simple_len(uint node)
{
    node = resolve_expr_node(node);
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
        return inner_len == 0u ? 0u : inner_len + (expr_neg_is_f32(node) ? 1u : 3u);
    }

    uint op = expr_binary_op_byte_for_node(node);
    uint left_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
    uint right_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT));
    return op == 0u || left_len == 0u || right_len == 0u ? 0u : left_len + right_len + 1u;
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
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = expr_atom_len(inner);
        if (expr_neg_is_f32(node))
        {
            if (byte_i < inner_len)
                return expr_atom_byte(inner, byte_i);
            return WASM_F32_NEG;
        }
        if (byte_i < 2u)
            return i32_const_byte(0u, byte_i);
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
    return expr_binary_op_byte_for_node(node);
}

uint method_receiver_node_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = resolve_expr_node(hir_call_callee_node[call_node]);
    if (!valid_node(callee_node) || hir_kind[callee_node] != HIR_MEMBER_EXPR)
        return INVALID;

    uint receiver = hir_member_receiver_node[callee_node];
    return valid_node(receiver) ? receiver : INVALID;
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

uint direct_call_abi_arg_node(uint call_node, uint arg_count, uint ordinal)
{
    uint explicit_arg_count = valid_node(call_node) ? hir_call_arg_count[call_node] : 0u;
    uint receiver = method_receiver_node_for_call(call_node);
    bool has_receiver_arg = valid_node(receiver) && arg_count == explicit_arg_count + 1u;
    if (has_receiver_arg)
    {
        if (ordinal == 0u)
            return receiver;
        return direct_call_arg_node(call_node, ordinal - 1u);
    }
    return direct_call_arg_node(call_node, ordinal);
}

uint direct_call_abi_arg_len(uint node, uint fn_token, uint ordinal)
{
    uint param_ty = call_param_type_value(fn_token, ordinal);
    if (param_ty >= TY_ARRAY_BASE)
    {
        uint aggregate_len = 0u;
        return aggregate_address_expr_len(node, aggregate_len) ? aggregate_len : 0u;
    }
    return expr_simple_len(node);
}

uint direct_call_abi_arg_byte(uint node, uint fn_token, uint ordinal, uint byte_i)
{
    uint param_ty = call_param_type_value(fn_token, ordinal);
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_address_expr_byte(node, byte_i);
    return expr_simple_byte(node, byte_i);
}

uint let_agg_direct_call_i32_fragment_byte(
    uint local_index,
    uint call_node,
    uint4 aux,
    uint byte_i)
{
    uint wasm_func_index = aux.x;
    uint offset = 0u;

    if (byte_i == offset)
        return WASM_CALL;
    offset += 1u;

    uint call_index_len = u32_leb_len(wasm_func_index);
    if (byte_i < offset + call_index_len)
        return u32_leb_byte(wasm_func_index, byte_i - offset);
    offset += call_index_len;

    return local_set_byte(local_index, byte_i - offset);
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
    if (meta.x != BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32)
        return;

    uint byte_i = body_byte_i - offset;
    uint arg_bytes = arg_bytes_for_fragment(token_i);
    if (byte_i < arg_bytes)
        return;
    byte_i -= arg_bytes;
    body_words[body_byte_i] =
        let_agg_direct_call_i32_fragment_byte(meta.y, meta.z, body_fragment_aux[token_i], byte_i);
}
