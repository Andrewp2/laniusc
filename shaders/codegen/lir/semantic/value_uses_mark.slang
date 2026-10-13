import hir_records;
import codegen.lir.semantic.common;
import gpu_index;

struct Params { uint n_hir_nodes; uint n_tokens; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> semantic_value_id;
StructuredBuffer<uint> semantic_enclosing_fn_by_hir;
RWStructuredBuffer<uint> semantic_value_used;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= count || semantic_enclosing_fn_by_hir[node] == 0u) return;
    HirCore core = compact_hir_core[node];
    if ((core.kind != HIR_NAME_EXPR && core.kind != HIR_PATH_EXPR &&
         core.kind != HIR_EXPR) || compact_hir_payload[node].a != HIR_EXPR_NAME)
        return;
    uint declaration = semantic_value_id[node];
    // Definitions and match pattern bindings point to their own token. Only
    // checked references to another declaration make its value necessary.
    if (declaration < gParams.n_tokens && declaration != core.token_start)
        InterlockedOr(semantic_value_used[declaration], 1u);
}
