// Build indirect dispatch arguments for passes that only need active HIR/tree nodes.

struct Params
{
    uint n;
    uint uses_ll1;
    uint n_node_blocks;
    uint n_prefix_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<uint> ll1_status;
RWStructuredBuffer<uint> tree_active_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_node_count()
{
    return gTree.uses_ll1 != 0u ? min(gTree.n, ll1_status[5u]) : gTree.n;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint groups = max(1u, (active_node_count() + WG_SIZE - 1u) / WG_SIZE);
    tree_active_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    tree_active_dispatch_args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    tree_active_dispatch_args[2u] = 1u;
}
