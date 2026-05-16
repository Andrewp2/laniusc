// x86_64 branch-block return statement projection.
//
// This pass scatters return statements that belong to if/else branch blocks
// into sparse block-keyed rows. Later value lowering consumes these rows
// instead of scanning all HIR nodes to rediscover returns inside branch blocks.

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

RWStructuredBuffer<uint4> x86_block_return_stmt_record;
RWStructuredBuffer<uint> x86_block_return_stmt_count;
RWStructuredBuffer<uint> x86_block_return_stmt_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_RETURN_STMT = 9u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint X86_BLOCK_RETURN_STMTS_OK = 1u;
static const uint X86_BLOCK_RETURN_STMT_BRANCH = 1u;

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

bool nearest_if_branch_block(uint ret_node, out uint if_node, out uint block_node)
{
    if_node = INVALID;
    block_node = INVALID;
    if (!valid_node(ret_node))
        return false;

    uint cur = ret_node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return false;
        if (hir_kind[p] == HIR_IF_STMT)
        {
            if_node = p;
            block_node = cur;
            return valid_node(block_node);
        }
        cur = p;
    }
    return false;
}

void scatter_block_return(uint ret_node)
{
    if (hir_kind[ret_node] != HIR_RETURN_STMT ||
        stmt_record_slot(ret_node, 0u) != STMT_RECORD_KIND_RETURN)
        return;

    uint if_node = INVALID;
    uint block_node = INVALID;
    if (!nearest_if_branch_block(ret_node, if_node, block_node))
        return;

    uint ret_expr = stmt_record_slot(ret_node, 1u);
    if (!valid_node(ret_expr))
        return;

    uint prior_count = 0u;
    InterlockedAdd(x86_block_return_stmt_count[block_node], 1u, prior_count);
    if (prior_count == 0u)
    {
        x86_block_return_stmt_record[block_node] =
            uint4(block_node, ret_node, ret_expr, X86_BLOCK_RETURN_STMT_BRANCH);
    }

    uint old_total = 0u;
    InterlockedAdd(x86_block_return_stmt_status[3u], 1u, old_total);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u)
    {
        x86_block_return_stmt_status[0u] = X86_BLOCK_RETURN_STMTS_OK;
        x86_block_return_stmt_status[1u] = 0u;
        x86_block_return_stmt_status[2u] = INVALID;
    }

    if (node_i >= active_hir_node_count())
        return;

    scatter_block_return(node_i);
}
