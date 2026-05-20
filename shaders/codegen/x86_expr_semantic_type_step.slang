// x86_64 expression numeric-type pointer-jump step.
//
// Each step doubles the distance followed through the expression inheritance
// relation seeded by x86_expr_semantic_type_init.

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
StructuredBuffer<uint> x86_expr_semantic_type_in;
StructuredBuffer<uint> x86_expr_semantic_type_link_in;

RWStructuredBuffer<uint> x86_expr_semantic_type_out;
RWStructuredBuffer<uint> x86_expr_semantic_type_link_out;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;

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
    if (!valid_node(node))
        return;

    uint ty = x86_expr_semantic_type_in[node];
    uint link = x86_expr_semantic_type_link_in[node];
    if (ty != TY_UNKNOWN || !valid_node(link) || link == node)
    {
        x86_expr_semantic_type_out[node] = ty;
        x86_expr_semantic_type_link_out[node] = INVALID;
        return;
    }

    uint link_ty = x86_expr_semantic_type_in[link];
    uint next_link = x86_expr_semantic_type_link_in[link];
    x86_expr_semantic_type_out[node] = link_ty;
    x86_expr_semantic_type_link_out[node] =
        link_ty == TY_UNKNOWN && valid_node(next_link) ? next_link : INVALID;
}
