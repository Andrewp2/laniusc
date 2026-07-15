// Reduce root-sorted expression depths to one minimum per 256-row block.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;

StructuredBuffer<uint> expr_order;
StructuredBuffer<uint2> expr_depth_state;
RWStructuredBuffer<uint> expr_depth_block_min;

static const uint INF = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

groupshared uint block_depth[WG_SIZE];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 gtid: SV_GroupThreadID)
{
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    if (block >= gExprRadix.n_blocks)
        return;

    uint row = block * WG_SIZE + gtid.x;
    uint node = row < gExprRadix.n_items ? expr_order[row] : INF;
    block_depth[gtid.x] = node < gExprRadix.n_items ? expr_depth_state[node].y : INF;
    GroupMemoryBarrierWithGroupSync();

    for (uint stride = WG_SIZE / 2u; stride != 0u; stride >>= 1u)
    {
        if (gtid.x < stride)
            block_depth[gtid.x] = min(block_depth[gtid.x], block_depth[gtid.x + stride]);
        GroupMemoryBarrierWithGroupSync();
    }

    if (gtid.x == 0u)
        expr_depth_block_min[block] = block_depth[0u];
}
