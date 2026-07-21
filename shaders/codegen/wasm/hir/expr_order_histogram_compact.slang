// Bucket-major radix histogram for dense compact-HIR expression identities.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> expr_same_end_rank;
StructuredBuffer<uint> expr_order_in;
RWStructuredBuffer<uint> expr_radix_histogram;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint bucket_count[256];

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
    uint lane = ltid.x;
    if (block >= gExprRadix.n_blocks) return;
    bucket_count[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();
    uint order_i = block * WG_SIZE + lane;
    if (order_i < gExprRadix.n_items)
    {
        uint bucket = compact_radix_key(expr_order_in[order_i]);
        InterlockedAdd(bucket_count[bucket], 1u);
    }
    GroupMemoryBarrierWithGroupSync();
    expr_radix_histogram[lane * gExprRadix.n_blocks + block] = bucket_count[lane];
}
