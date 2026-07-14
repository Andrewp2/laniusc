// Scatter the non-argument tail of left-call binary direct-call fragments.

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
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
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
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_RETURN = 0x0fu;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I32_SUB = 0x6bu;
static const uint WASM_F32_NEG = 0x8cu;
static const uint WASM_F32_SUB = 0x93u;
static const uint WASM_F32_MUL = 0x94u;
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
        bool done = (current == 0 && !sign_bit_set) || (current == -1 && sign_bit_set) || i == 4u;
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
        bool done = (current == 0 && !sign_bit_set) || (current == -1 && sign_bit_set) || i == 4u;
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

uint local_decl_initializer_type(uint decl_token)
{
    uint init_expr = valid_token(decl_token) ? body_let_init_expr_by_decl_token[decl_token] : INVALID;
    init_expr = resolve_expr_node(init_expr);
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
    return global_exclusive_prefix(decl_token, WG_SIZE, wasm_agg_local_base_by_token, wasm_agg_local_block_prefix);
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
    if (function_param_local_index(decl_token, owner_fn, local_index))
    {
        len = 1u + u32_leb_len(local_index);
        return true;
    }
    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        len = 1u + i32_sleb_len(base_address);
        return true;
    }
    if (function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        len = 1u + u32_leb_len(local_index);
        return true;
    }
    return false;
}

uint aggregate_address_expr_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint local_index = INVALID;
    if (function_param_local_index(decl_token, owner_fn, local_index))
        return local_get_byte(local_index, byte_i);
    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        return i32_const_byte(base_address, byte_i);
    }
    if (function_non_param_local_index(decl_token, owner_fn, local_index))
        return local_get_byte(local_index, byte_i);
    return 0u;
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
    uint member_name = valid_node(node) ? hir_member_name_token[node] : INVALID;
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
    uint receiver = hir_member_receiver_node[node];
    uint address_len = 0u;
    if (field_index == INVALID || !aggregate_address_expr_len(receiver, address_len))
        return 0u;
    if (byte_i < address_len)
        return aggregate_address_expr_byte(receiver, byte_i);
    uint op = aggregate_member_field_type(node) == TY_FLOAT ? WASM_F32_LOAD : WASM_I32_LOAD;
    return memarg_load_byte(op, field_index * 4u, byte_i - address_len);
}

uint expr_atom_len(uint node)
{
    node = resolve_expr_node(node);
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

bool expr_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    if (expr_form(node) == HIR_EXPR_FLOAT)
        return true;
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return aggregate_member_field_type(node) == TY_FLOAT;
    if (expr_form(node) == HIR_EXPR_NAME)
        return visible_type_for_token(expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN)) == TY_FLOAT;
    return false;
}

uint expr_binary_op_byte(uint node)
{
    uint form = expr_form(node);
    if (expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ||
        expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_RIGHT)))
    {
        if (form == HIR_EXPR_SUB) return WASM_F32_SUB;
        if (form == HIR_EXPR_MUL) return WASM_F32_MUL;
    }
    if (form == HIR_EXPR_SUB) return WASM_I32_SUB;
    return 0u;
}

uint expr_side_len(uint node)
{
    node = resolve_expr_node(node);
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return atom_len;
    uint form = expr_form(node);
    if (form == HIR_EXPR_NEG)
    {
        uint inner_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
        return inner_len == 0u ? 0u : inner_len + (expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ? 1u : 3u);
    }
    uint op = expr_binary_op_byte(node);
    if (op == 0u)
        return 0u;
    uint left_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
    uint right_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT));
    return left_len == 0u || right_len == 0u ? 0u : left_len + right_len + 1u;
}

uint expr_side_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return expr_atom_byte(node, byte_i);
    uint form = expr_form(node);
    if (form == HIR_EXPR_NEG)
    {
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = expr_atom_len(inner);
        if (expr_atom_is_f32(inner))
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
    return expr_binary_op_byte(node);
}

bool fragment_for_body_byte(uint body_byte_i, out uint fragment_i)
{
    fragment_i = INVALID;
    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = body_prefix_for_token(mid);
        uint end = start + body_fragment_len[mid];
        if (end <= body_byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= gScan.n_items)
        return false;
    uint start = body_prefix_for_token(lo);
    uint len = body_fragment_len[lo];
    if (body_byte_i < start || body_byte_i >= start + len)
        return false;
    fragment_i = lo;
    return true;
}

uint tail_byte(uint fragment_i, uint4 meta, uint4 aux, uint byte_i)
{
    uint arg_bytes = arg_bytes_for_fragment(fragment_i);
    if (byte_i < arg_bytes)
        return 0u;
    uint tail_i = byte_i - arg_bytes;
    uint call_tail_len = 1u + wasm_call_index_len(aux.x);
    if (tail_i == 0u)
        return WASM_CALL;
    if (tail_i < call_tail_len)
        return wasm_call_index_byte(aux.x, tail_i - 1u);
    uint expr_i = tail_i - call_tail_len;
    uint expr_len = expr_side_len(meta.w);
    if (expr_i < expr_len)
        return expr_side_byte(meta.w, expr_i);
    if (expr_i == expr_len)
        return aux.w & 0xffu;
    return local_set_byte(meta.y, expr_i - expr_len - 1u);
}

uint return_tail_byte(uint fragment_i, uint4 meta, uint4 aux, uint byte_i)
{
    uint arg_bytes = arg_bytes_for_fragment(fragment_i);
    uint call_tail_len = 1u + wasm_call_index_len(aux.x);
    uint packed_op = meta.w;
    uint op = packed_op & 0xffu;
    uint call_side = packed_op >> 8u;
    uint expr_len = expr_side_len(meta.z);

    if (call_side == 0u)
    {
        if (byte_i < arg_bytes)
            return 0u;
        uint tail_i = byte_i - arg_bytes;
        if (tail_i == 0u)
            return WASM_CALL;
        if (tail_i < call_tail_len)
            return wasm_call_index_byte(aux.x, tail_i - 1u);
        uint expr_i = tail_i - call_tail_len;
        if (expr_i < expr_len)
            return expr_side_byte(meta.z, expr_i);
        if (expr_i == expr_len)
            return op;
        return WASM_RETURN;
    }

    if (byte_i < expr_len)
        return expr_side_byte(meta.z, byte_i);
    uint arg_i = byte_i - expr_len;
    if (arg_i < arg_bytes)
        return 0u;
    uint call_i = arg_i - arg_bytes;
    if (call_i == 0u)
        return WASM_CALL;
    if (call_i < call_tail_len)
        return wasm_call_index_byte(aux.x, call_i - 1u);
    if (call_i == call_tail_len)
        return op;
    return WASM_RETURN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u)
        return;
    uint fragment_i = INVALID;
    if (!fragment_for_body_byte(body_byte_i, fragment_i))
        return;
    uint4 meta = body_fragment_meta[fragment_i];
    if (meta.x != BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 &&
        meta.x != BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32)
        return;
    uint offset = body_prefix_for_token(fragment_i);
    uint byte_i = body_byte_i - offset;
    uint arg_bytes = arg_bytes_for_fragment(fragment_i);
    uint arg_base =
        meta.x == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 &&
        (meta.w >> 8u) != 0u
            ? expr_side_len(meta.z)
            : 0u;
    if (byte_i >= arg_base && byte_i < arg_base + arg_bytes)
        return;
    body_words[body_byte_i] =
        meta.x == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32
            ? return_tail_byte(fragment_i, meta, body_fragment_aux[fragment_i], byte_i)
            : tail_byte(fragment_i, meta, body_fragment_aux[fragment_i], byte_i);
}
