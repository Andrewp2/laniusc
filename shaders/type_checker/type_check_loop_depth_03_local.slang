import prefix_scan;

struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<int> loop_delta;

RWStructuredBuffer<int> loop_depth_inblock;
RWStructuredBuffer<int> block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint i = block_idx * WG_SIZE + lane;
    int value = i < gParams.n_tokens ? loop_delta[i] : 0;
    int inclusive = prefix_scan_i32_256(lane, value);
    if (i < gParams.n_tokens)
        loop_depth_inblock[i] = inclusive;
    if (lane + 1u == WG_SIZE)
        block_sum[block_idx] = inclusive;
}
