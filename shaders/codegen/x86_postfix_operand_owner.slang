// x86_64 postfix operand ownership projection.
//
// Parser expression-result roots already map postfix wrappers to the operator
// node that semantically produces the value. This pass scatters that relation
// by operand/operator node so instruction counting does not need to rediscover
// postfix ownership with direct parent probes.

import atomics;
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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_result_root_node;

RWStructuredBuffer<uint> x86_postfix_operand_owner;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node) || hir_kind[node] != HIR_POSTFIX_EXPR)
        return;

    uint resolved = hir_expr_result_root_node[node];
    if (!valid_node(resolved) || hir_kind[resolved] != HIR_UNARY_EXPR)
        return;

    atomic_u32_min(x86_postfix_operand_owner, resolved, node);
}
