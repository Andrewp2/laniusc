// Dense-HIR counterpart for scalar return-expression byte scatter.

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

static const uint BODY_FRAGMENT_RETURN_EXPR_COMPACT_I32 = 61u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_COMPACT_I32 = 65u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_COMPACT_I32 = 66u;
static const uint BODY_FRAGMENT_LET_EXPR_COMPACT_I32 = 67u;
static const uint BODY_FRAGMENT_STMT_EXPR_COMPACT = 71u;
static const uint WASM_RETURN = 0x0fu;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint compact_return_body_prefix(uint token_i)
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
        uint mid_start = compact_return_body_prefix(mid);
        uint mid_end = mid_start + body_fragment_len[mid];
        if (mid_end <= body_byte_i) lo = mid + 1u;
        else hi = mid;
    }
    uint token_i = lo;
    if (token_i >= gScan.n_items) return;

    uint len = body_fragment_len[token_i];
    uint offset = compact_return_body_prefix(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len) return;
    uint4 meta = body_fragment_meta[token_i];
    bool is_return = meta.x == BODY_FRAGMENT_RETURN_EXPR_COMPACT_I32;
    bool is_assign = meta.x == BODY_FRAGMENT_ASSIGN_EXPR_COMPACT_I32;
    bool is_compound_assign =
        meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_COMPACT_I32;
    bool is_let = meta.x == BODY_FRAGMENT_LET_EXPR_COMPACT_I32;
    bool is_stmt = meta.x == BODY_FRAGMENT_STMT_EXPR_COMPACT;
    uint expr = is_return || is_stmt ? meta.y : meta.z;
    if ((!is_return && !is_assign && !is_compound_assign && !is_let && !is_stmt) ||
        !valid_node(expr)) return;

    uint byte_i = body_byte_i - offset;
    uint prefix_len = is_compound_assign ? local_get_len(meta.y) : 0u;
    if (byte_i < prefix_len)
    {
        body_words[offset + byte_i] = local_get_byte(meta.y, byte_i);
        return;
    }
    uint expr_byte = byte_i - prefix_len;
    uint expr_len = compact_expr_tree_len(expr);
    if (expr_byte < expr_len)
    {
        body_words[offset + byte_i] = compact_expr_tree_byte(expr, expr_byte);
        return;
    }
    uint suffix_byte = expr_byte - expr_len;
    if (is_stmt)
        return;
    else if (is_return)
        body_words[offset + byte_i] = WASM_RETURN;
    else if (is_compound_assign && suffix_byte == 0u)
        body_words[offset + byte_i] = compact_assign_op_byte(meta.w & 0xffu, meta.w >> 8u);
    else
        body_words[offset + byte_i] = local_set_byte(
            meta.y, suffix_byte - (is_compound_assign ? 1u : 0u));
}
