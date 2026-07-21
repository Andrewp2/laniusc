// Dense-HIR numeric range-for byte scatter.

import gpu_index;
import prefix_scan;
import compact_expr_common;
import compact_expr_byte_common;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> status;
StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_FOR_OPEN_RANGE_COMPACT_I32 = 74u;
static const uint BODY_FRAGMENT_FOR_CLOSE_RANGE_COMPACT_I32 = 75u;
static const uint WASM_BLOCK = 0x02u;
static const uint WASM_LOOP = 0x03u;
static const uint WASM_END = 0x0bu;
static const uint WASM_BR = 0x0cu;
static const uint WASM_BR_IF = 0x0du;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint compact_range_body_prefix(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint compact_for_open_byte(uint binding, uint range, uint end_local, uint byte_i)
{
    if (!valid_node(range)) return 0u;
    HirPayload payload = compact_hir_payload[range];
    uint start = payload.b;
    uint end = payload.c;
    uint start_len = compact_expr_tree_len(start);
    if (byte_i < start_len) return compact_expr_tree_byte(start, byte_i);

    uint binding_set_start = start_len;
    uint binding_set_len = local_set_len(binding);
    if (byte_i < binding_set_start + binding_set_len)
        return local_set_byte(binding, byte_i - binding_set_start);

    uint end_start = binding_set_start + binding_set_len;
    uint end_len = compact_expr_tree_len(end);
    if (byte_i < end_start + end_len)
        return compact_expr_tree_byte(end, byte_i - end_start);

    uint end_set_start = end_start + end_len;
    uint end_set_len = local_set_len(end_local);
    if (byte_i < end_set_start + end_set_len)
        return local_set_byte(end_local, byte_i - end_set_start);

    uint block_start = end_set_start + end_set_len;
    if (byte_i == block_start) return WASM_BLOCK;
    if (byte_i == block_start + 1u) return WASM_BLOCK_TYPE_EMPTY;
    if (byte_i == block_start + 2u) return WASM_LOOP;
    if (byte_i == block_start + 3u) return WASM_BLOCK_TYPE_EMPTY;

    uint condition_start = block_start + 4u;
    uint binding_get_len = local_get_len(binding);
    if (byte_i < condition_start + binding_get_len)
        return local_get_byte(binding, byte_i - condition_start);
    uint end_get_start = condition_start + binding_get_len;
    uint end_get_len = local_get_len(end_local);
    if (byte_i < end_get_start + end_get_len)
        return local_get_byte(end_local, byte_i - end_get_start);
    uint ge_i = end_get_start + end_get_len;
    if (byte_i == ge_i) return WASM_I32_GE_S;
    if (byte_i == ge_i + 1u) return WASM_BR_IF;
    if (byte_i == ge_i + 2u) return 1u;
    if (byte_i == ge_i + 3u) return WASM_BLOCK;
    return WASM_BLOCK_TYPE_EMPTY;
}

uint compact_for_close_byte(uint binding, uint byte_i)
{
    if (byte_i == 0u) return WASM_END;
    uint get_start = 1u;
    uint get_len = local_get_len(binding);
    if (byte_i < get_start + get_len)
        return local_get_byte(binding, byte_i - get_start);
    uint one_start = get_start + get_len;
    if (byte_i < one_start + 2u) return i32_const_byte(1u, byte_i - one_start);
    uint add_i = one_start + 2u;
    if (byte_i == add_i) return WASM_I32_ADD;
    uint set_start = add_i + 1u;
    uint set_len = local_set_len(binding);
    if (byte_i < set_start + set_len)
        return local_set_byte(binding, byte_i - set_start);
    uint br_i = set_start + set_len;
    if (byte_i == br_i) return WASM_BR;
    if (byte_i == br_i + 1u) return 0u;
    return WASM_END;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u) return;

    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_start = compact_range_body_prefix(mid);
        uint mid_end = mid_start + body_fragment_len[mid];
        if (mid_end <= body_byte_i) lo = mid + 1u;
        else hi = mid;
    }
    uint token_i = lo;
    if (token_i >= gScan.n_items) return;

    uint len = body_fragment_len[token_i];
    uint offset = compact_range_body_prefix(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len) return;
    uint4 meta = body_fragment_meta[token_i];
    uint byte_i = body_byte_i - offset;
    if (meta.x == BODY_FRAGMENT_FOR_OPEN_RANGE_COMPACT_I32)
        body_words[offset + byte_i] = compact_for_open_byte(meta.y, meta.z, meta.w, byte_i);
    else if (meta.x == BODY_FRAGMENT_FOR_CLOSE_RANGE_COMPACT_I32)
        body_words[offset + byte_i] = compact_for_close_byte(meta.y, byte_i);
}
