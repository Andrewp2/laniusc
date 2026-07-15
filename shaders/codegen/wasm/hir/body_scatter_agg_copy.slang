// Scatter aggregate local, scalar-field-store, and direct-copy fragments.
// Keep this entry point at minimum Slang optimization until its independent
// fragment families are split; higher optimization currently expands SPIR-V.

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
}
