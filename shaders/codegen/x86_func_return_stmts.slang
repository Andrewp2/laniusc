// x86_64 per-function return statement projection.
//
// This pass scatters top-level HIR return statements into declaration-stable
// per-function records. Later body planning consumes these rows directly
// instead of scanning all HIR nodes for each function.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_stmt_record;

RWStructuredBuffer<uint4> x86_func_return_stmt_record;
RWStructuredBuffer<uint> x86_func_return_stmt_count;
RWStructuredBuffer<uint> x86_func_return_stmt_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint X86_FUNC_RETURN_STMT_TOP_LEVEL = 1u;
static const uint X86_FUNC_RETURN_STMT_ERR_DUPLICATE = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint stmt_record_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

uint owning_function_node(uint node, out bool nested_if)
{
    nested_if = false;
    if (!valid_node(node))
        return INVALID;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        uint p_kind = hir_kind[p];
        if (p_kind == HIR_FN)
            return p;
        if (p_kind == HIR_IF_STMT)
            nested_if = true;
        cur = p;
    }
    return INVALID;
}

void scatter_return_stmt(uint ret_node)
{
    if (hir_kind[ret_node] != HIR_RETURN_STMT ||
        stmt_record_slot(ret_node, 0u) != STMT_RECORD_KIND_RETURN)
        return;

    bool nested_if = false;
    uint fn_node = owning_function_node(ret_node, nested_if);
    if (!valid_node(fn_node) || nested_if)
        return;

    uint ret_expr = stmt_record_slot(ret_node, 1u);
    if (!valid_node(ret_expr))
        return;

    uint prior_count = 0u;
    InterlockedAdd(x86_func_return_stmt_count[fn_node], 1u, prior_count);
    if (prior_count == 0u)
    {
        x86_func_return_stmt_record[fn_node] =
            uint4(fn_node, ret_node, ret_expr, X86_FUNC_RETURN_STMT_TOP_LEVEL);
    }
    else
    {
        x86_func_return_stmt_status[0u] = 0u;
        x86_func_return_stmt_status[1u] = X86_FUNC_RETURN_STMT_ERR_DUPLICATE;
        uint old_detail = 0u;
        InterlockedMin(x86_func_return_stmt_status[2u], ret_node, old_detail);
    }

    uint old_total = 0u;
    InterlockedAdd(x86_func_return_stmt_status[3u], 1u, old_total);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i >= active_hir_node_count())
        return;

    scatter_return_stmt(node_i);
}
