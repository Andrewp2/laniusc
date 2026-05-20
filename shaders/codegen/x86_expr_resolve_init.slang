// x86_64 expression-forward pointer-jump seed.
//
// Parser HIR uses HIR_EXPR_FORWARD nodes for syntax wrappers. Later backend
// passes consume this resolved-node table instead of each shader walking the
// forward chain locally.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_expr_record;

RWStructuredBuffer<uint> x86_expr_resolved_node;
RWStructuredBuffer<uint> x86_expr_resolve_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;

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

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint left = expr_left(node);
    if (expr_form(node) == HIR_EXPR_FORWARD)
    {
        x86_expr_resolved_node[node] = valid_node(left) ? left : INVALID;
        x86_expr_resolve_link[node] = valid_node(left) ? left : INVALID;
        return;
    }

    x86_expr_resolved_node[node] = node;
    x86_expr_resolve_link[node] = INVALID;
}
