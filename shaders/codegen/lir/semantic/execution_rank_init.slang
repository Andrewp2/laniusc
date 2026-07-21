// Seed target-independent expression depth. Pointer jumping over the complete
// compact expression-parent forest gives every node its distance to the
// result root. Lowering reverses that depth to obtain child-before-parent
// postorder without a serial tree walk.

import codegen.lir.semantic.common;
import gpu_index;

struct Params { uint n_hir_nodes; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_expr_parent;
RWStructuredBuffer<uint> execution_rank_link;
RWStructuredBuffer<uint> execution_rank;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= gParams.n_hir_nodes) return;
    if (node >= hir_count)
    {
        execution_rank_link[node] = LIR_INVALID;
        execution_rank[node] = 0u;
        return;
    }

    uint parent = compact_expr_parent[node];
    bool linked = parent != LIR_INVALID && parent < hir_count;
    execution_rank_link[node] = linked ? parent : LIR_INVALID;
    execution_rank[node] = linked ? 1u : 0u;
}
