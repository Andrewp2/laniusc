struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<int> if_depth_inblock;
StructuredBuffer<int> block_prefix;

RWStructuredBuffer<int> if_depth;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    // An exclusive scan's first block prefix is always zero. The hierarchy
    // has no dispatch level when there is only one block, so its workspace
    // row is intentionally unwritten and may contain data from an aliased
    // earlier pass.
    int prefix = i < WG_SIZE ? 0 : block_prefix[i / WG_SIZE];
    if_depth[i] = prefix + if_depth_inblock[i];
}
