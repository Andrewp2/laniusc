// Bucket-major u8 histogram for one expression-root radix byte.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> hir_expr_forest_root_node;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> expr_same_end_rank;
StructuredBuffer<uint> expr_order_in;
RWStructuredBuffer<uint> expr_radix_histogram;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint bucket_count[256];

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
    uint lane = ltid.x;
    if (block >= gExprRadix.n_blocks)
        return;
    bucket_count[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    uint order_i = block * WG_SIZE + lane;
    if (order_i < gExprRadix.n_items)
    {
        uint node = expr_order_in[order_i];
        uint bucket = radix_key(node);
        InterlockedAdd(bucket_count[bucket], 1u);
    }
    GroupMemoryBarrierWithGroupSync();
    expr_radix_histogram[lane * gExprRadix.n_blocks + block] = bucket_count[lane];
}
