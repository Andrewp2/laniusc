// Parallel pointer-jump step for compact expression ancestors: each round
// follows up to POINTER_JUMP_HOPS input links, so the reach of a link grows
// by that factor per round (`pointer_jump_hop_pairs` in lowering_ir.rs).

import codegen.lir.semantic.common;
import gpu_index;

struct Params { uint n_hir_nodes; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> execution_rank_link_in;
StructuredBuffer<uint> execution_rank_in;
RWStructuredBuffer<uint> execution_rank_link_out;
RWStructuredBuffer<uint> execution_rank_out;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint POINTER_JUMP_HOPS = 16u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= hir_count) return;

    uint link = execution_rank_link_in[node];
    uint rank = execution_rank_in[node];
    for (uint hop = 1u; hop < POINTER_JUMP_HOPS; ++hop)
    {
        if (link == LIR_INVALID || link >= hir_count)
            break;
        rank += execution_rank_in[link];
        link = execution_rank_link_in[link];
    }
    bool linked = link != LIR_INVALID && link < hir_count;
    execution_rank_link_out[node] = linked ? execution_rank_link_in[link] : LIR_INVALID;
    execution_rank_out[node] = rank + (linked ? execution_rank_in[link] : 0u);
}
