// Stable scatter using the globally scanned bucket-major histogram.

import stable_radix_scatter;

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> hir_expr_forest_root_node;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> expr_same_end_rank;
StructuredBuffer<uint> expr_order_in;
StructuredBuffer<uint> expr_radix_histogram_prefix;
StructuredBuffer<uint> expr_radix_block_prefix;
RWStructuredBuffer<uint> expr_order_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint radix_key(uint node)
{
    uint key_step = gExprRadix.key_step;
    uint value = 0u;
    if (key_step < 4u)
        value = ~expr_same_end_rank[node];
    else if (key_step < 8u)
        value = hir_token_end[node];
    else
    {
        value = hir_expr_forest_root_node[node];
    }
    return (value >> ((key_step & 3u) * 8u)) & 0xffu;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    if (block >= gExprRadix.n_blocks)
        return;
    uint lane = ltid.x;
    uint order_i = block * WG_SIZE + lane;
    bool active = order_i < gExprRadix.n_items;
    uint node = active ? expr_order_in[order_i] : 0u;
    uint key = active ? radix_key(node) : INVALID;
    uint sorted_key = INVALID;
    uint sorted_node = 0u;
    uint local_rank = 0u;
    stable_radix_sort_byte_rank(
        lane,
        key,
        node,
        sorted_key,
        sorted_node,
        local_rank);
    if (sorted_key == INVALID)
        return;
    uint histogram_i = sorted_key * gExprRadix.n_blocks + block;
    uint scan_block = histogram_i / WG_SIZE;
    uint prior_blocks = scan_block == 0u ? 0u : expr_radix_block_prefix[scan_block - 1u];
    uint dst = expr_radix_histogram_prefix[histogram_i] +
               prior_blocks +
               local_rank;
    expr_order_out[dst] = sorted_node;
}
