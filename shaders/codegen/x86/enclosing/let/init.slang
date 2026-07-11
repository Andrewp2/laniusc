// x86_64 nearest enclosing let-statement seed.
//
// This pass seeds a parent-link relation so x86_node_inst_gen can identify the
// let initializer that owns an aggregate call/value without walking parents
// inside the generator shader.

import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_call_context_stmt_node;
StructuredBuffer<uint> x86_tree_parent;

RWStructuredBuffer<uint> x86_enclosing_let_node;
RWStructuredBuffer<uint> x86_enclosing_let_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_CALL_EXPR = 19u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

bool is_let_node(uint node)
{
    if (!valid_node(node))
        return false;

    uint kind = hir_kind[node];
    uint stmt_kind = stmt_slot(node, 0u);
    return (kind == HIR_LET_STMT || kind == HIR_STMT) &&
           stmt_kind == STMT_RECORD_KIND_LET;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint parent = x86_tree_parent[node];
    uint call_context = hir_kind[node] == HIR_CALL_EXPR
                            ? hir_call_context_stmt_node[node]
                            : INVALID;
    if (is_let_node(call_context))
    {
        x86_enclosing_let_node[node] = call_context;
        x86_enclosing_let_link[node] = INVALID;
        return;
    }
    if (is_let_node(parent))
    {
        x86_enclosing_let_node[node] = parent;
        x86_enclosing_let_link[node] = INVALID;
        return;
    }

    x86_enclosing_let_node[node] = INVALID;
    x86_enclosing_let_link[node] = valid_node(parent) ? parent : INVALID;
}
