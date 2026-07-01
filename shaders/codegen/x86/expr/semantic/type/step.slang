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
StructuredBuffer<uint> x86_expr_semantic_record_in;

RWStructuredBuffer<uint> x86_expr_semantic_record_out;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint EXPR_SEMANTIC_LINK_MASK = 0x3fffffffu;
static const uint EXPR_SEMANTIC_UINT_FLAG = 0x40000000u;
static const uint EXPR_SEMANTIC_FLOAT_FLAG = 0x80000000u;

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

uint record_type(uint record)
{
    if ((record & EXPR_SEMANTIC_UINT_FLAG) != 0u)
        return TY_UINT;
    if ((record & EXPR_SEMANTIC_FLOAT_FLAG) != 0u)
        return TY_FLOAT;
    return TY_UNKNOWN;
}

uint record_link(uint record)
{
    uint link = record & EXPR_SEMANTIC_LINK_MASK;
    return link == EXPR_SEMANTIC_LINK_MASK ? INVALID : link;
}

uint pack_expr_semantic_record(uint ty, uint link)
{
    uint packed_link =
        valid_node(link) && link < EXPR_SEMANTIC_LINK_MASK
            ? link
            : EXPR_SEMANTIC_LINK_MASK;
    uint type_bits = ty == TY_UINT ? EXPR_SEMANTIC_UINT_FLAG
                   : ty == TY_FLOAT ? EXPR_SEMANTIC_FLOAT_FLAG
                   : 0u;
    return type_bits | packed_link;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint record = x86_expr_semantic_record_in[node];
    uint ty = record_type(record);
    uint link = record_link(record);
    if (ty != TY_UNKNOWN || !valid_node(link) || link == node)
    {
        x86_expr_semantic_record_out[node] = pack_expr_semantic_record(ty, INVALID);
        return;
    }

    uint link_record = x86_expr_semantic_record_in[link];
    uint link_ty = record_type(link_record);
    uint next_link = record_link(link_record);
    x86_expr_semantic_record_out[node] = pack_expr_semantic_record(
        link_ty,
        link_ty == TY_UNKNOWN && valid_node(next_link) ? next_link : INVALID);
}
