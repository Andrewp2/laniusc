// x86_64 short-circuit RHS ownership seed.
//
// This pass marks the RHS root of logical &&/|| expressions, then seeds a
// parent-link relation so x86_short_circuit_rhs_step can propagate that owner
// to every descendant without bounded parent probing in instruction generation.

import gpu_index;

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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_tree_parent;

RWStructuredBuffer<uint> x86_short_circuit_rhs_node;
RWStructuredBuffer<uint> x86_short_circuit_rhs_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;

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

uint expr_right(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

bool logical_form_short_circuits(uint form)
{
    return form == HIR_EXPR_AND || form == HIR_EXPR_OR;
}

bool is_short_circuit_rhs_root(uint node)
{
    uint parent = valid_node(node) ? x86_tree_parent[node] : INVALID;
    if (!valid_node(parent) || !logical_form_short_circuits(expr_form(parent)))
        return false;

    uint rhs = expr_right(parent);
    uint resolved_rhs = resolve_expr(rhs);
    return node == rhs || node == resolved_rhs;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    if (is_short_circuit_rhs_root(node))
    {
        x86_short_circuit_rhs_node[node] = node;
        x86_short_circuit_rhs_link[node] = INVALID;
        return;
    }

    x86_short_circuit_rhs_node[node] = INVALID;
    uint parent = x86_tree_parent[node];
    x86_short_circuit_rhs_link[node] = valid_node(parent) ? parent : INVALID;
}
