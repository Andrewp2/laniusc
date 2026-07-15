// Publish each expression root's total byte count and unsupported-row count.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> hir_expr_forest_root_node;
StructuredBuffer<uint> expr_order;
StructuredBuffer<uint4> expr_contribution;
StructuredBuffer<uint4> expr_contribution_local_prefix;
StructuredBuffer<uint4> expr_contribution_block_prefix;
StructuredBuffer<uint4> expr_root_prefix;
RWStructuredBuffer<uint2> expr_root_total;
RWStructuredBuffer<uint2> expr_root_order_range;
RWStructuredBuffer<uint2> expr_node_span;

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
    uint next_root = i + 1u < gExprRadix.n_items
        ? hir_expr_forest_root_node[expr_order[i + 1u]]
        : INVALID;
    uint block = i / WG_SIZE;
    uint4 prior_blocks = block == 0u
        ? uint4(0u, 0u, 0u, 0u)
        : expr_contribution_block_prefix[block - 1u];
    uint4 inclusive = prior_blocks + expr_contribution_local_prefix[i] +
                      expr_contribution[i];
    uint node = expr_order[i];
    expr_node_span[node] = uint2(
        inclusive.x - expr_contribution[i].x - expr_root_prefix[root].x,
        expr_contribution[i].x);
    if (root == next_root)
        return;
    expr_root_order_range[root].y = i + 1u;
    expr_root_total[root] = (inclusive - expr_root_prefix[root]).xy;
}
