// Pointer-jump expression-forest links to their final roots in O(log n) passes.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExprForest;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_forest_root_in;
RWStructuredBuffer<uint> hir_expr_forest_root_out;

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
    uint active = active_node_count();
    if (node >= active)
        return;

    uint link = hir_expr_forest_root_in[node];
    hir_expr_forest_root_out[node] = link != INVALID && link < active ?
        hir_expr_forest_root_in[link] :
        node;
}
