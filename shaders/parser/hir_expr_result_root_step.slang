// Pointer-jump parser expression result edges into direct result roots.
//
// `hir_expr_result_node` remains the local edge relation. This pass family
// materializes the transitive result root with one graph hop per dispatch, so
// consumers do not need bounded in-shader chases through expression wrappers.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirExprResultRoot;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_expr_result_root_in;

RWStructuredBuffer<uint> hir_expr_result_root_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExprResultRoot.uses_ll1 != 0u
        ? min(gHirExprResultRoot.n, ll1_status[5u])
        : gHirExprResultRoot.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_node_count())
        return;

    uint root = hir_expr_result_root_in[node];
    if (!valid_node(root))
    {
        hir_expr_result_root_out[node] = INVALID;
        return;
    }

    uint next = hir_expr_result_root_in[root];
    hir_expr_result_root_out[node] = valid_node(next) ? next : root;
}
