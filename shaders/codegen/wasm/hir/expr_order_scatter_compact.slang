// Stable radix scatter for dense compact-HIR expression identities.

import stable_radix_scatter;

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> expr_same_end_rank;
StructuredBuffer<uint> expr_order_in;
StructuredBuffer<uint> expr_radix_histogram_prefix;
StructuredBuffer<uint> expr_radix_block_prefix;
RWStructuredBuffer<uint> expr_order_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint compact_radix_key(uint node)
{
    uint step = gExprRadix.key_step;
    uint value = step < 4u ? ~expr_same_end_rank[node]
               : step < 8u ? compact_hir_core[node].token_end
                           : compact_expr_root[node];
    return (value >> ((step & 3u) * 8u)) & 0xffu;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    if (block >= gExprRadix.n_blocks) return;
    uint lane = ltid.x;
    uint order_i = block * WG_SIZE + lane;
    bool active = order_i < gExprRadix.n_items;
    uint node = active ? expr_order_in[order_i] : 0u;
    uint key = active ? compact_radix_key(node) : INVALID;
    uint local_rank = stable_radix_byte_local_rank(lane, key, active);
    if (!active) return;
    uint histogram_i = key * gExprRadix.n_blocks + block;
    uint scan_block = histogram_i / WG_SIZE;
    uint prior_blocks = scan_block == 0u ? 0u : expr_radix_block_prefix[scan_block - 1u];
    uint dst = expr_radix_histogram_prefix[histogram_i] + prior_blocks + local_rank;
    expr_order_out[dst] = node;
}
