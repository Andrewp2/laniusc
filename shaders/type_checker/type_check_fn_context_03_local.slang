struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> fn_event_index;

RWStructuredBuffer<uint> fn_event_inblock;
RWStructuredBuffer<uint> block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

groupshared uint s_event_index[256];

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
    uint value = i < gParams.n_tokens ? fn_event_index[i] : 0u;

    s_event_index[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < WG_SIZE; offs <<= 1u)
    {
        uint next = s_event_index[lane];
        if (lane >= offs)
            next = max(next, s_event_index[lane - offs]);
        GroupMemoryBarrierWithGroupSync();
        s_event_index[lane] = next;
        GroupMemoryBarrierWithGroupSync();
    }

    if (i < gParams.n_tokens)
        fn_event_inblock[i] = s_event_index[lane];
    if (lane + 1u == WG_SIZE)
        block_sum[block_idx] = s_event_index[lane];
}
