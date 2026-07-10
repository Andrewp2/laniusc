// Scatter array allocation, literal-atom stores, and indexed scalar loads.

import body_arg_byte_common;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;

RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_LET_ARRAY_I32 = 30u;
static const uint BODY_FRAGMENT_ARRAY_STORE_ATOM_I32 = 56u;
static const uint BODY_FRAGMENT_ASSIGN_INDEX_I32 = 57u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_INDEX_I32 = 58u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_EXPR_INDEX = 26u;
static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint WASM_I32_STORE = 0x36u;
static const uint WASM_F32_STORE = 0x38u;
static const uint WG_SIZE = 256u;

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint memarg_store_byte(uint op, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return 0u;
}

uint compound_assign_op_byte(uint op, bool f32)
{
    if (f32)
    {
        if (op == ASSIGN_OP_ADD) return WASM_F32_ADD;
        if (op == ASSIGN_OP_SUB) return WASM_F32_SUB;
        if (op == ASSIGN_OP_MUL) return WASM_F32_MUL;
        if (op == ASSIGN_OP_DIV) return WASM_F32_DIV;
        return 0u;
    }
    if (op == ASSIGN_OP_ADD) return WASM_I32_ADD;
    if (op == ASSIGN_OP_SUB) return WASM_I32_SUB;
    if (op == ASSIGN_OP_MUL) return WASM_I32_MUL;
    if (op == ASSIGN_OP_DIV) return WASM_I32_DIV_S;
    if (op == ASSIGN_OP_MOD) return WASM_I32_REM_S;
    return 0u;
}

bool lean_array_atom_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
    {
        len = local_get_len(local_index);
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

uint lean_array_atom_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
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

bool lean_array_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    if (expr_form(node) == HIR_EXPR_FLOAT)
        return true;
    uint token = hir_token_pos[node];
    return valid_token(token) && visible_type_for_token(token) == TY_FLOAT;
}

bool array_local_for_expr(uint node, out uint local_index)
{
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint init_expr = valid_token(decl_token)
                         ? resolve_expr_node(body_let_init_expr_by_decl_token[decl_token])
                         : INVALID;
    return valid_node(init_expr) &&
           hir_kind[init_expr] == HIR_ARRAY_EXPR &&
           function_non_param_local_index(
               decl_token,
               node_enclosing_fn_token(node),
               local_index);
}

bool index_expr_and_len(
    uint node,
    out uint array_local,
    out uint index_node,
    out uint len)
{
    array_local = INVALID;
    index_node = INVALID;
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_INDEX)
        return false;
    index_node = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint index_len = 0u;
    if (!array_local_for_expr(
            expr_record_slot(node, EXPR_RECORD_LEFT),
            array_local) ||
        !lean_array_atom_and_len(index_node, index_len))
    {
        return false;
    }
    len = local_get_len(array_local) + index_len + 7u;
    return true;
}

bool index_expr_is_f32(uint node)
{
    node = resolve_expr_node(node);
    return valid_node(node) &&
           valid_token(hir_token_pos[node]) &&
           visible_type_for_token(hir_token_pos[node]) == TY_FLOAT;
}

uint index_expr_byte(uint node, uint byte_i)
{
    uint array_local = INVALID;
    uint index_node = INVALID;
    uint len = 0u;
    if (!index_expr_and_len(node, array_local, index_node, len))
        return 0u;

    uint array_get_len = local_get_len(array_local);
    if (byte_i < array_get_len)
        return local_get_byte(array_local, byte_i);
    uint index_len = 0u;
    if (!lean_array_atom_and_len(index_node, index_len))
        return 0u;
    uint index_start = array_get_len;
    if (byte_i < index_start + index_len)
        return lean_array_atom_byte(index_node, byte_i - index_start);
    uint scale_start = index_start + index_len;
    if (byte_i < scale_start + 2u)
        return i32_const_byte(4u, byte_i - scale_start);
    if (byte_i == scale_start + 2u)
        return WASM_I32_MUL;
    if (byte_i == scale_start + 3u)
        return WASM_I32_ADD;
    uint load_op = index_expr_is_f32(node) ? WASM_F32_LOAD : WASM_I32_LOAD;
    return memarg_load_byte(load_op, 0u, byte_i - scale_start - 4u);
}

uint assign_index_expr_byte(
    uint target_local,
    uint index_node,
    uint assign_op,
    uint byte_i)
{
    uint array_local = INVALID;
    uint index_value_node = INVALID;
    uint index_len = 0u;
    if (!index_expr_and_len(
            index_node,
            array_local,
            index_value_node,
            index_len))
        return 0u;

    uint offset = 0u;
    if (assign_op != ASSIGN_OP_SET)
    {
        uint target_get_len = local_get_len(target_local);
        if (byte_i < target_get_len)
            return local_get_byte(target_local, byte_i);
        offset = target_get_len;
    }
    if (byte_i < offset + index_len)
        return index_expr_byte(index_node, byte_i - offset);
    offset += index_len;
    if (assign_op != ASSIGN_OP_SET)
    {
        if (byte_i == offset)
            return compound_assign_op_byte(
                assign_op,
                index_expr_is_f32(index_node));
        offset += 1u;
    }
    return local_set_byte(target_local, byte_i - offset);
}

uint let_array_i32_fragment_byte(uint local_index, uint base_address, uint byte_i)
{
    uint const_len = 1u + i32_sleb_len(base_address);
    if (byte_i < const_len)
        return i32_const_byte(base_address, byte_i);
    return local_set_byte(local_index, byte_i - const_len);
}

uint array_store_atom_byte(uint address, uint value_node, uint byte_i)
{
    uint address_len = 1u + i32_sleb_len(address);
    if (byte_i < address_len)
        return i32_const_byte(address, byte_i);

    uint expr_len = 0u;
    if (!lean_array_atom_and_len(value_node, expr_len))
        return 0u;
    uint expr_start = address_len;
    if (byte_i < expr_start + expr_len)
        return lean_array_atom_byte(value_node, byte_i - expr_start);

    uint op = lean_array_atom_is_f32(value_node) ? WASM_F32_STORE : WASM_I32_STORE;
    return memarg_store_byte(op, byte_i - expr_start - expr_len);
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
    uint byte_i = body_byte_i - offset;
    if (meta.x == BODY_FRAGMENT_LET_ARRAY_I32)
    {
        body_words[offset + byte_i] =
            let_array_i32_fragment_byte(meta.y, meta.z, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_ARRAY_STORE_ATOM_I32)
    {
        uint expr_len = 0u;
        if (lean_array_atom_and_len(meta.z, expr_len))
            body_words[offset + byte_i] = array_store_atom_byte(meta.y, meta.z, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_ASSIGN_INDEX_I32 ||
        meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_INDEX_I32)
    {
        uint array_local = INVALID;
        uint index_node = INVALID;
        uint index_len = 0u;
        if (!index_expr_and_len(meta.z, array_local, index_node, index_len))
            return;
        uint target_set_len = 1u + u32_leb_len(meta.y);
        uint expected_len = meta.x == BODY_FRAGMENT_ASSIGN_INDEX_I32
                                ? index_len + target_set_len
                                : local_get_len(meta.y) + index_len + 1u +
                                  target_set_len;
        if (expected_len != len)
            return;
        body_words[offset + byte_i] =
            assign_index_expr_byte(meta.y, meta.z, meta.w, byte_i);
    }
}
