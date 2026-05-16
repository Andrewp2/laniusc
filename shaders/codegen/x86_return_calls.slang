// x86_64 top-level return call projection.
//
// This pass scatters the call node contained by a supported top-level return
// statement into a return-keyed row. Value lowering consumes the row directly
// instead of scanning the HIR subtree under the return expression.

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
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint4> x86_func_return_stmt_record;
StructuredBuffer<uint> x86_func_return_stmt_count;

RWStructuredBuffer<uint4> x86_return_call_record;
RWStructuredBuffer<uint> x86_return_call_count;
RWStructuredBuffer<uint> x86_return_call_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_RETURN_STMT = 9u;
static const uint X86_RETURN_CALLS_OK = 1u;
static const uint X86_RETURN_CALL_ERR_DUPLICATE = 1u;
static const uint X86_FUNC_RETURN_STMT_TOP_LEVEL = 1u;
static const uint X86_RETURN_CALL_BRANCH = 2u;

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

uint first_call_descendant(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint end = min(subtree_end[node], active_hir_node_count());
    [loop]
    for (uint cur = node; cur < end; cur += 1u)
    {
        if (hir_kind[cur] == HIR_CALL_EXPR)
            return cur;
    }
    return INVALID;
}

uint enclosing_return_node(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        if (hir_kind[p] == HIR_RETURN_STMT)
            return p;
        cur = p;
    }
    return INVALID;
}

bool is_projected_top_return(uint fn_node, uint ret_node)
{
    if (!valid_node(fn_node) || !valid_node(ret_node) ||
        x86_func_return_stmt_count[fn_node] != 1u)
        return false;

    uint4 record = x86_func_return_stmt_record[fn_node];
    return record.x == fn_node &&
           record.y == ret_node &&
           record.w == X86_FUNC_RETURN_STMT_TOP_LEVEL;
}

void publish_duplicate_error(uint ret_node)
{
    x86_return_call_status[0u] = 0u;
    x86_return_call_status[1u] = X86_RETURN_CALL_ERR_DUPLICATE;
    uint old_detail = 0u;
    InterlockedMin(x86_return_call_status[2u], ret_node, old_detail);
}

void publish_return_call(uint ret_node, uint call_node, uint fn_node, uint return_kind)
{
    if (!valid_node(ret_node) || !valid_node(call_node) || !valid_node(fn_node))
        return;

    uint prior_count = 0u;
    InterlockedAdd(x86_return_call_count[ret_node], 1u, prior_count);
    if (prior_count == 0u)
    {
        x86_return_call_record[ret_node] =
            uint4(ret_node, call_node, fn_node, return_kind);
    }
    else
    {
        publish_duplicate_error(ret_node);
    }

    uint old_total = 0u;
    InterlockedAdd(x86_return_call_status[3u], 1u, old_total);
}

void project_top_return_call(uint fn_node)
{
    if (!valid_node(fn_node) || x86_func_return_stmt_count[fn_node] != 1u)
        return;

    uint4 record = x86_func_return_stmt_record[fn_node];
    if (record.x != fn_node || record.w != X86_FUNC_RETURN_STMT_TOP_LEVEL ||
        !valid_node(record.y))
        return;

    uint call_node = first_call_descendant(record.z);
    if (valid_node(call_node))
    {
        publish_return_call(
            record.y,
            call_node,
            fn_node,
            X86_FUNC_RETURN_STMT_TOP_LEVEL);
    }
}

void scatter_branch_return_call(uint call_node)
{
    if (hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint fn_node = x86_node_func[call_node];
    uint ret_node = enclosing_return_node(call_node);
    if (!valid_node(fn_node) || !valid_node(ret_node))
        return;
    if (is_projected_top_return(fn_node, ret_node))
        return;

    publish_return_call(ret_node, call_node, fn_node, X86_RETURN_CALL_BRANCH);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u)
    {
        x86_return_call_status[0u] = X86_RETURN_CALLS_OK;
        x86_return_call_status[1u] = 0u;
        x86_return_call_status[2u] = INVALID;
    }

    if (node_i >= active_hir_node_count())
        return;

    project_top_return_call(node_i);
    scatter_branch_return_call(node_i);
}
