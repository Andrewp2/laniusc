// Publish the global exclusive contribution prefix at each expression root.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> hir_expr_forest_root_node;
StructuredBuffer<uint> expr_order;
StructuredBuffer<uint4> expr_contribution_local_prefix;
StructuredBuffer<uint4> expr_contribution_block_prefix;
RWStructuredBuffer<uint4> expr_root_prefix;
RWStructuredBuffer<uint2> expr_root_order_range;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (i >= gExprRadix.n_items)
        return;
    uint root = hir_expr_forest_root_node[expr_order[i]];
    if (root == INVALID)
        return;
    uint previous_root = i == 0u ? INVALID : hir_expr_forest_root_node[expr_order[i - 1u]];
    if (root == previous_root)
        return;
    uint block = i / WG_SIZE;
    uint4 prior_blocks = block == 0u
        ? uint4(0u, 0u, 0u, 0u)
        : expr_contribution_block_prefix[block - 1u];
    expr_root_prefix[root] = expr_contribution_local_prefix[i] + prior_blocks;
    expr_root_order_range[root].x = i;
}
