// Dense-HIR scalar if/while condition byte scatter.

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

static const uint BODY_FRAGMENT_IF_OPEN_EXPR_COMPACT_I32 = 72u;
static const uint BODY_FRAGMENT_WHILE_OPEN_EXPR_COMPACT_I32 = 73u;
static const uint WASM_BLOCK = 0x02u;
static const uint WASM_LOOP = 0x03u;
static const uint WASM_IF = 0x04u;
static const uint WASM_BR_IF = 0x0du;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint compact_control_body_prefix(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
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
        uint mid_start = compact_control_body_prefix(mid);
        uint mid_end = mid_start + body_fragment_len[mid];
        if (mid_end <= body_byte_i) lo = mid + 1u;
        else hi = mid;
    }
    uint token_i = lo;
    if (token_i >= gScan.n_items) return;

    uint len = body_fragment_len[token_i];
    uint offset = compact_control_body_prefix(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len) return;
    uint4 meta = body_fragment_meta[token_i];
    bool is_if = meta.x == BODY_FRAGMENT_IF_OPEN_EXPR_COMPACT_I32;
    bool is_while = meta.x == BODY_FRAGMENT_WHILE_OPEN_EXPR_COMPACT_I32;
    if (!is_if && !is_while) return;

    uint byte_i = body_byte_i - offset;
    uint expr = meta.y;
    if (!valid_node(expr)) return;
    uint expr_len = compact_expr_tree_len(expr);
    if (is_if)
    {
        if (byte_i < expr_len)
            body_words[offset + byte_i] = compact_expr_tree_byte(expr, byte_i);
        else
            body_words[offset + byte_i] =
                byte_i == expr_len ? WASM_IF : WASM_BLOCK_TYPE_EMPTY;
        return;
    }

    if (byte_i == 0u) body_words[offset + byte_i] = WASM_BLOCK;
    else if (byte_i == 1u) body_words[offset + byte_i] = WASM_BLOCK_TYPE_EMPTY;
    else if (byte_i == 2u) body_words[offset + byte_i] = WASM_LOOP;
    else if (byte_i == 3u) body_words[offset + byte_i] = WASM_BLOCK_TYPE_EMPTY;
    else
    {
        uint expr_byte = byte_i - 4u;
        if (expr_byte < expr_len)
            body_words[offset + byte_i] = compact_expr_tree_byte(expr, expr_byte);
        else if (expr_byte == expr_len)
            body_words[offset + byte_i] = WASM_I32_EQZ;
        else if (expr_byte == expr_len + 1u)
            body_words[offset + byte_i] = WASM_BR_IF;
        else
            body_words[offset + byte_i] = 1u;
    }
}
