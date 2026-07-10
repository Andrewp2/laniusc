// Scatter aggregate local, scalar-field-store, and direct-copy fragments.

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

static const uint BODY_FRAGMENT_AGG_FIELD_STORE_I32 = 40u;
static const uint BODY_FRAGMENT_AGG_DIRECT_COPY_I32 = 43u;
static const uint BODY_FRAGMENT_LET_AGG_MEMBER_COPY_I32 = 52u;
static const uint BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32 = 53u;
static const uint BODY_FRAGMENT_ASSIGN_MEMBER_COMPOUND_EXPR_I32 = 54u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint WASM_I32_STORE = 0x36u;
static const uint WASM_F32_STORE = 0x38u;
static const uint WASM_PREFIX_MISC = 0xfcu;
static const uint WASM_MEMORY_COPY = 0x0au;
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

uint member_access_len(uint field_index)
{
    return 2u + u32_leb_len(field_index * 4u);
}

uint member_access_byte(uint op, uint field_index, uint byte_i)
{
    return memarg_load_byte(op, field_index * 4u, byte_i);
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

bool member_assign_rhs_and_len(uint node, out uint len)
{
    len = 0u;
    if (expr_non_call_atom_and_len(node, len))
        return true;

    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint form = expr_form(node);
    uint left_len = 0u;
    uint right_len = 0u;
    if (!expr_binary_op_supported(form) ||
        expr_binary_op_byte_for_node(node) == 0u ||
        !expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), left_len) ||
        !expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_RIGHT), right_len))
    {
        return false;
    }
    len = left_len + right_len + 1u;
    return true;
}

uint member_assign_rhs_byte(uint node, uint byte_i)
{
    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len))
        return expr_non_call_atom_byte(node, byte_i);

    node = resolve_expr_node(node);
    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint left_len = 0u;
    uint right_len = 0u;
    if (!valid_node(node) ||
        !expr_non_call_atom_and_len(left, left_len) ||
        !expr_non_call_atom_and_len(right, right_len))
    {
        return 0u;
    }
    if (byte_i < left_len)
        return expr_non_call_atom_byte(left, byte_i);
    if (byte_i < left_len + right_len)
        return expr_non_call_atom_byte(right, byte_i - left_len);
    return expr_binary_op_byte_for_node(node);
}

bool scalar_member_target_info(
    uint node,
    out uint receiver,
    out uint address_len,
    out uint field_index,
    out uint field_ty)
{
    receiver = INVALID;
    address_len = 0u;
    field_index = INVALID;
    field_ty = TY_UNKNOWN;
    node = member_expr_node_from_expr(node);
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return false;

    uint member_name = hir_member_name_token[node];
    receiver = hir_member_receiver_node[node];
    if (!valid_token(member_name) ||
        !aggregate_address_expr_and_len(receiver, address_len))
        return false;

    field_index = member_result_field_index[member_name];
    field_ty = visible_type_for_token(member_name);
    return field_index != INVALID && field_ty < TY_ARRAY_BASE;
}

uint assign_member_expr_byte(uint target_node, uint rhs_node, uint byte_i)
{
    uint receiver = INVALID;
    uint address_len = 0u;
    uint field_index = INVALID;
    uint field_ty = TY_UNKNOWN;
    if (!scalar_member_target_info(
            target_node,
            receiver,
            address_len,
            field_index,
            field_ty))
        return 0u;

    if (byte_i < address_len)
        return aggregate_address_expr_byte(receiver, byte_i);

    uint rhs_len = 0u;
    if (!member_assign_rhs_and_len(rhs_node, rhs_len))
        return 0u;
    if (byte_i < address_len + rhs_len)
        return member_assign_rhs_byte(rhs_node, byte_i - address_len);

    uint store_op = field_ty == TY_FLOAT ? WASM_F32_STORE : WASM_I32_STORE;
    return member_access_byte(store_op, field_index, byte_i - address_len - rhs_len);
}

uint assign_member_compound_expr_byte(
    uint target_node,
    uint rhs_node,
    uint assign_op,
    uint byte_i)
{
    uint receiver = INVALID;
    uint address_len = 0u;
    uint field_index = INVALID;
    uint field_ty = TY_UNKNOWN;
    if (!scalar_member_target_info(
            target_node,
            receiver,
            address_len,
            field_index,
            field_ty))
        return 0u;

    if (byte_i < address_len)
        return aggregate_address_expr_byte(receiver, byte_i);
    uint offset = address_len;
    if (byte_i < offset + address_len)
        return aggregate_address_expr_byte(receiver, byte_i - offset);
    offset += address_len;

    uint access_len = member_access_len(field_index);
    uint load_op = field_ty == TY_FLOAT ? WASM_F32_LOAD : WASM_I32_LOAD;
    if (byte_i < offset + access_len)
        return member_access_byte(load_op, field_index, byte_i - offset);
    offset += access_len;

    uint rhs_len = 0u;
    if (!member_assign_rhs_and_len(rhs_node, rhs_len))
        return 0u;
    if (byte_i < offset + rhs_len)
        return member_assign_rhs_byte(rhs_node, byte_i - offset);
    offset += rhs_len;

    if (byte_i == offset)
        return compound_assign_op_byte(assign_op, field_ty == TY_FLOAT);
    uint store_op = field_ty == TY_FLOAT ? WASM_F32_STORE : WASM_I32_STORE;
    return member_access_byte(store_op, field_index, byte_i - offset - 1u);
}

uint aggregate_direct_copy_i32_fragment_byte(uint local_index, uint decl_token, uint byte_i)
{
    uint width = valid_token(decl_token) ? wasm_agg_local_width_by_token[decl_token] : 0u;
    uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
    uint base_len = 1u + i32_sleb_len(base_address);
    if (byte_i < base_len)
        return i32_const_byte(base_address, byte_i);

    uint offset = base_len;
    uint local_ref_len = local_get_len(local_index);
    if (byte_i < offset + local_ref_len)
        return local_get_byte(local_index, byte_i - offset);
    offset += local_ref_len;

    uint copy_len_len = 1u + i32_sleb_len(width * 4u);
    if (byte_i < offset + copy_len_len)
        return i32_const_byte(width * 4u, byte_i - offset);
    offset += copy_len_len;

    if (byte_i == offset)
        return WASM_PREFIX_MISC;
    if (byte_i == offset + 1u)
        return WASM_MEMORY_COPY;
    if (byte_i == offset + 2u || byte_i == offset + 3u)
        return 0u;
    offset += 4u;

    if (byte_i < offset + base_len)
        return i32_const_byte(base_address, byte_i - offset);
    offset += base_len;

    return local_set_byte(local_index, byte_i - offset);
}

uint aggregate_member_copy_i32_fragment_byte(
    uint local_index,
    uint decl_token,
    uint source_node,
    uint byte_i)
{
    uint width = valid_token(decl_token) ? wasm_agg_local_width_by_token[decl_token] : 0u;
    uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
    uint base_len = 1u + i32_sleb_len(base_address);
    if (byte_i < base_len)
        return i32_const_byte(base_address, byte_i);

    uint offset = base_len;
    uint source_len = 0u;
    bool source_is_member =
        valid_node(resolve_expr_node(source_node)) &&
        hir_kind[resolve_expr_node(source_node)] == HIR_MEMBER_EXPR;
    bool source_ok = source_is_member
                         ? aggregate_member_address_and_len(source_node, source_len)
                         : aggregate_address_expr_and_len(source_node, source_len);
    if (!source_ok)
        return 0u;
    if (byte_i < offset + source_len)
        return source_is_member
                   ? aggregate_member_address_byte(source_node, byte_i - offset)
                   : aggregate_address_expr_byte(source_node, byte_i - offset);
    offset += source_len;

    uint width_len = 1u + i32_sleb_len(width * 4u);
    if (byte_i < offset + width_len)
        return i32_const_byte(width * 4u, byte_i - offset);
    offset += width_len;

    if (byte_i == offset)
        return WASM_PREFIX_MISC;
    if (byte_i == offset + 1u)
        return WASM_MEMORY_COPY;
    if (byte_i == offset + 2u || byte_i == offset + 3u)
        return 0u;
    offset += 4u;

    if (byte_i < offset + base_len)
        return i32_const_byte(base_address, byte_i - offset);
    offset += base_len;
    return local_set_byte(local_index, byte_i - offset);
}

uint aggregate_field_store_atom_byte(uint address, uint value_node, uint byte_i)
{
    uint address_len = 1u + i32_sleb_len(address);
    if (byte_i < address_len)
        return i32_const_byte(address, byte_i);

    uint expr_len = 0u;
    if (!expr_non_call_atom_and_len(value_node, expr_len))
        return 0u;
    uint expr_start = address_len;
    if (byte_i < expr_start + expr_len)
        return expr_non_call_atom_byte(value_node, byte_i - expr_start);

    uint op = expr_atom_is_f32(value_node) ? WASM_F32_STORE : WASM_I32_STORE;
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
    if (meta.x == BODY_FRAGMENT_AGG_FIELD_STORE_I32)
    {
        uint expr_len = 0u;
        if (expr_non_call_atom_and_len(meta.z, expr_len))
            body_words[offset + byte_i] = aggregate_field_store_atom_byte(meta.y, meta.z, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_AGG_DIRECT_COPY_I32)
    {
        body_words[offset + byte_i] = aggregate_direct_copy_i32_fragment_byte(meta.y, meta.z, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_LET_AGG_MEMBER_COPY_I32)
    {
        body_words[offset + byte_i] =
            aggregate_member_copy_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32 ||
        meta.x == BODY_FRAGMENT_ASSIGN_MEMBER_COMPOUND_EXPR_I32)
    {
        uint receiver = INVALID;
        uint address_len = 0u;
        uint field_index = INVALID;
        uint field_ty = TY_UNKNOWN;
        uint rhs_len = 0u;
        if (!scalar_member_target_info(
                meta.y,
                receiver,
                address_len,
                field_index,
                field_ty) ||
            !member_assign_rhs_and_len(meta.z, rhs_len))
            return;
        uint access_len = member_access_len(field_index);
        uint expected_len = meta.x == BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32
                                ? address_len + rhs_len + access_len
                                : address_len * 2u + access_len * 2u + rhs_len + 1u;
        if (expected_len != len)
            return;
        body_words[offset + byte_i] = meta.x == BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32
            ? assign_member_expr_byte(meta.y, meta.z, byte_i)
            : assign_member_compound_expr_byte(meta.y, meta.z, meta.w, byte_i);
        return;
    }
}
