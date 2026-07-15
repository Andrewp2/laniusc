// Seed one pointer-jump link per HIR node for expression-forest roots.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExprForest;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_parent_node;
RWStructuredBuffer<uint> hir_expr_forest_root_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExprForest.uses_status_count != 0u ?
        min(gHirExprForest.n, tree_count_status[5u]) :
        gHirExprForest.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_node_count())
        return;
    uint parent = hir_expr_parent_node[node];
    hir_expr_forest_root_node[node] = parent != INVALID && parent < active_node_count() ? parent : node;
}
