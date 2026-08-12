// Follow a bounded run of parser expression result edges into direct roots.
//
// The expression-field pass publishes the local edge relation. This pass
// materializes its transitive result root without exposing wrapper chains to
// consumers.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExprResultRoot;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_result_root_in;

RWStructuredBuffer<uint> hir_expr_result_root_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExprResultRoot.uses_status_count != 0u
        ? min(gHirExprResultRoot.n, tree_count_status[5u])
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

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        uint next = hir_expr_result_root_in[root];
        if (!valid_node(next) || next == root)
            break;
        root = next;
    }
    hir_expr_result_root_out[node] = root;
}
