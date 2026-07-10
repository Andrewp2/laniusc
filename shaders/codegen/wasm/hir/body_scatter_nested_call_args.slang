// Scatter nested direct-call argument bytes from scanned argument records.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<ScanParams> gBodyScan;
ConstantBuffer<ScanParams> gArgScan;

StructuredBuffer<uint> status;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint4> wasm_agg_call_arg_meta;
StructuredBuffer<uint4> wasm_agg_call_arg_aux;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 31u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 = 27u;
static const uint ARG_WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
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
    uint encoded = enclosing_fn[token];
    return encoded == 0u ? INVALID : encoded - 1u;
}

uint wasm_global_exclusive_prefix(
    uint item_i,
    uint workgroup_size,
    StructuredBuffer<uint> local_prefix,
    StructuredBuffer<uint> block_prefix)
{
    uint block_i = item_i / workgroup_size;
    uint prior_blocks = block_i == 0u ? 0u : block_prefix[block_i - 1u];
    return prior_blocks + local_prefix[item_i];
}

uint body_prefix_for_fragment(uint fragment_i)
{
    return wasm_global_exclusive_prefix(
        fragment_i,
        ARG_WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint arg_count_prefix_for_fragment(uint fragment_i)
{
    return wasm_global_exclusive_prefix(
        fragment_i,
        ARG_WG_SIZE,
        wasm_agg_call_arg_count_local_prefix,
        wasm_agg_call_arg_count_block_prefix);
}

uint arg_byte_prefix_for_record(uint record_i)
{
    return wasm_global_exclusive_prefix(
        record_i,
        ARG_WG_SIZE,
        wasm_agg_call_arg_byte_local_prefix,
        wasm_agg_call_arg_byte_block_prefix);
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
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        if ((current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u)
        {
            return i + 1u;
        }
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
    return wasm_global_exclusive_prefix(
        decl_token,
        ARG_WG_SIZE,
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
    if (!valid_token(fn_token) || ordinal >= call_param_count[fn_token])
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
    local_index = function_param_abi_count(fn_token) + decl_token;
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

bool name_decl_token(uint node, out uint decl_token)
{
    decl_token = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    return valid_token(decl_token);
}

bool name_local_index(uint node, out uint local_index)
{
    local_index = INVALID;
    uint decl_token = INVALID;
    if (!name_decl_token(node, decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    if (function_param_local_index(decl_token, owner_fn, local_index))
        return true;
    if (body_let_init_expr_by_decl_token[decl_token] == INVALID)
        return false;
    return function_non_param_local_index(decl_token, owner_fn, local_index);
}

bool name_const_value(uint node, out uint value)
{
    value = 0u;
    uint decl_token = INVALID;
    if (!name_decl_token(node, decl_token))
        return false;

    uint2 record = wasm_const_value_record[decl_token];
    if (record.x != WASM_CONST_VALUE_LITERAL)
        return false;
    value = record.y;
    return true;
}

bool scalar_atom_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    uint local_index = INVALID;
    uint value = 0u;
    if (form == HIR_EXPR_NAME && name_local_index(node, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    if (form == HIR_EXPR_NAME && name_const_value(node, value))
    {
        len = 1u + i32_sleb_len(value);
        return true;
    }
    if (form == HIR_EXPR_INT)
    {
        len = 1u + i32_sleb_len(hir_expr_int_value[node]);
        return true;
    }
    if (form == HIR_EXPR_FLOAT)
    {
        len = 5u;
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        len = 2u;
        return true;
    }
    return false;
}

uint scalar_atom_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint form = expr_form(node);
    uint local_index = INVALID;
    uint value = 0u;
    if (form == HIR_EXPR_NAME && name_local_index(node, local_index))
        return local_get_byte(local_index, byte_i);
    if (form == HIR_EXPR_NAME && name_const_value(node, value))
        return i32_const_byte(value, byte_i);
    if (form == HIR_EXPR_INT)
        return i32_const_byte(hir_expr_int_value[node], byte_i);
    if (form == HIR_EXPR_FLOAT)
        return f32_const_byte(hir_expr_float_bits[node], byte_i);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
    return 0u;
}

bool aggregate_name_address_and_len(uint node, out uint len)
{
    len = 0u;
    uint decl_token = INVALID;
    if (!name_decl_token(node, decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    uint local_index = INVALID;
    if (function_param_local_index(decl_token, owner_fn, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        len = 1u + i32_sleb_len(base_address);
        return true;
    }
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE &&
        function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    return false;
}

uint aggregate_name_address_byte(uint node, uint byte_i)
{
    uint decl_token = INVALID;
    if (!name_decl_token(node, decl_token))
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
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE &&
        function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        return local_get_byte(local_index, byte_i);
    }
    return 0u;
}

uint call_fn_token_for_call(uint call_node)
{
    uint site_token = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    if (valid_token(site_token) && valid_token(call_fn_index[site_token]))
        return call_fn_index[site_token];

    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        if (valid_token(member_token) && valid_token(call_fn_index[member_token]))
            return call_fn_index[member_token];
    }
    return INVALID;
}

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
}

uint method_member_node_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR
               ? callee_node
               : INVALID;
}

bool direct_call_has_receiver_arg(uint call_node, uint fn_token)
{
    if (!valid_token(fn_token))
        return false;
    uint member_node = method_member_node_for_call(call_node);
    if (!valid_node(member_node) || !valid_node(hir_member_receiver_node[member_node]))
        return false;
    return call_param_count[fn_token] == hir_call_arg_count[call_node] + 1u;
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
    uint node = row < active_hir_node_count() ? call_arg_row_node[row] : INVALID;
    return valid_node(node) ? node : INVALID;
}

uint direct_call_abi_arg_node(uint call_node, uint fn_token, uint ordinal)
{
    if (direct_call_has_receiver_arg(call_node, fn_token))
    {
        if (ordinal == 0u)
        {
            uint member_node = method_member_node_for_call(call_node);
            return valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
        }
        return direct_call_arg_node(call_node, ordinal - 1u);
    }
    return direct_call_arg_node(call_node, ordinal);
}

bool nested_arg_piece_and_len(uint node, uint param_ty, out uint len)
{
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_name_address_and_len(node, len);
    return scalar_atom_and_len(node, len);
}

uint nested_arg_piece_byte(uint node, uint param_ty, uint byte_i)
{
    if (param_ty >= TY_ARRAY_BASE)
        return aggregate_name_address_byte(node, byte_i);
    return scalar_atom_byte(node, byte_i);
}

uint arg_byte_base_for_fragment(uint4 fragment_meta)
{
    if (fragment_meta.x == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 &&
        (fragment_meta.w >> 8u) != 0u)
    {
        uint side_len = 0u;
        if (scalar_atom_and_len(fragment_meta.z, side_len))
            return side_len;
    }
    if (fragment_meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
        return local_get_len(fragment_meta.y);
    return 0u;
}

bool record_for_arg_global_byte(uint arg_global_byte, out uint record_i)
{
    record_i = INVALID;
    uint lo = 0u;
    uint hi = gArgScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = arg_byte_prefix_for_record(mid);
        uint end = start + wasm_agg_call_arg_len[mid];
        if (end <= arg_global_byte)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= gArgScan.n_items)
        return false;

    uint start = arg_byte_prefix_for_record(lo);
    uint len = wasm_agg_call_arg_len[lo];
    if (arg_global_byte < start || arg_global_byte >= start + len)
        return false;

    record_i = lo;
    return true;
}

uint body_byte_for_arg_byte(uint record_i, uint arg_global_byte)
{
    uint fragment_i = wasm_agg_call_arg_meta[record_i].x;
    if (fragment_i == INVALID)
        return INVALID;

    uint first_record = arg_count_prefix_for_fragment(fragment_i);
    uint fragment_arg_start = arg_byte_prefix_for_record(first_record);
    uint4 fragment_meta = body_fragment_meta[fragment_i];
    return body_prefix_for_fragment(fragment_i) +
           arg_byte_base_for_fragment(fragment_meta) +
           (arg_global_byte - fragment_arg_start);
}

uint nested_direct_call_byte(uint call_node, uint byte_i)
{
    uint fn_token = call_fn_token_for_call(call_node);
    if (!supported_function_token(fn_token))
        return 0u;

    uint wasm_func_index = wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT;
    uint arg_count = call_param_count[fn_token];
    uint offset = 0u;
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_abi_arg_node(call_node, fn_token, i);
        uint param_ty = call_param_type_value(fn_token, i);
        uint arg_len = 0u;
        if (!nested_arg_piece_and_len(arg_node, param_ty, arg_len) || arg_len == 0u)
            return 0u;
        if (byte_i < offset + arg_len)
            return nested_arg_piece_byte(arg_node, param_ty, byte_i - offset);
        offset += arg_len;
    }

    if (byte_i == offset)
        return WASM_CALL;
    return u32_leb_byte(wasm_func_index, byte_i - offset - 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint arg_global_byte = linear_dispatch_id(tid);
    if (arg_global_byte >= gArgScan.out_capacity || status[2u] != 0u)
        return;

    uint record_i = INVALID;
    if (!record_for_arg_global_byte(arg_global_byte, record_i))
        return;

    uint4 arg_meta = wasm_agg_call_arg_meta[record_i];
    uint4 arg_aux = wasm_agg_call_arg_aux[record_i];
    uint call_node = resolve_expr_node(arg_meta.z);
    if (!valid_node(call_node) ||
        hir_kind[call_node] != HIR_CALL_EXPR ||
        arg_aux.y == TY_STRING ||
        arg_aux.y >= TY_ARRAY_BASE)
    {
        return;
    }

    uint body_byte_i = body_byte_for_arg_byte(record_i, arg_global_byte);
    if (body_byte_i == INVALID || body_byte_i >= gBodyScan.out_capacity)
        return;

    uint record_start = arg_byte_prefix_for_record(record_i);
    body_words[body_byte_i] =
        nested_direct_call_byte(call_node, arg_global_byte - record_start);
}
