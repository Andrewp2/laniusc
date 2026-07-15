// Scatter scalar member assignment fragments separately from aggregate copies.

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
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;

RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32 = 53u;
static const uint BODY_FRAGMENT_ASSIGN_MEMBER_COMPOUND_EXPR_I32 = 54u;
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

uint assign_member_expr_byte(
    uint receiver,
    uint address_len,
    uint field_index,
    uint field_ty,
    uint rhs_len,
    uint byte_i)
{
    if (byte_i < address_len)
        return aggregate_address_expr_byte(receiver, byte_i);
    if (byte_i < address_len + rhs_len)
        return 0u;

    uint store_op = field_ty == TY_FLOAT ? WASM_F32_STORE : WASM_I32_STORE;
    return member_access_byte(store_op, field_index, byte_i - address_len - rhs_len);
}

uint assign_member_compound_expr_byte(
    uint receiver,
    uint address_len,
    uint field_index,
    uint field_ty,
    uint rhs_len,
    uint assign_op,
    uint byte_i)
{
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

    if (byte_i < offset + rhs_len)
        return 0u;
    offset += rhs_len;

    if (byte_i == offset)
        return compound_assign_op_byte(assign_op, field_ty == TY_FLOAT);
    uint store_op = field_ty == TY_FLOAT ? WASM_F32_STORE : WASM_I32_STORE;
    return member_access_byte(store_op, field_index, byte_i - offset - 1u);
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
    if (meta.x != BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32 &&
        meta.x != BODY_FRAGMENT_ASSIGN_MEMBER_COMPOUND_EXPR_I32)
        return;

    uint4 aux = body_fragment_aux[token_i];
    uint receiver = meta.y;
    uint address_len = aux.x;
    uint field_index = aux.y;
    uint field_ty = aux.z;
    if (!valid_node(receiver) || address_len == 0u || field_index == INVALID ||
        field_ty >= TY_ARRAY_BASE)
        return;
    uint access_len = member_access_len(field_index);
    uint fixed_len = meta.x == BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32
                         ? address_len + access_len
                         : address_len * 2u + access_len * 2u + 1u;
    if (fixed_len >= len)
        return;
    uint rhs_len = len - fixed_len;
    uint expected_len = meta.x == BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32
                            ? address_len + rhs_len + access_len
                            : address_len * 2u + access_len * 2u + rhs_len + 1u;
    if (expected_len != len)
        return;

    uint byte_i = body_byte_i - offset;
    body_words[offset + byte_i] = meta.x == BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32
        ? assign_member_expr_byte(receiver, address_len, field_index, field_ty, rhs_len, byte_i)
        : assign_member_compound_expr_byte(
              receiver,
              address_len,
              field_index,
              field_ty,
              rhs_len,
              meta.w,
              byte_i);
}
