import codegen.lir.semantic.common;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
RWStructuredBuffer<uint> semantic_local_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (hir >= gParams.n_hir_nodes) return;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (hir < hir_count)
    {
        HirCore core = compact_hir_core[hir];
        HirPayload payload = compact_hir_payload[hir];
        bool source_local = (core.kind == HIR_LET_STMT ||
            (core.kind == HIR_STMT &&
             (payload.a == HIR_STMT_LET || payload.a == HIR_STMT_CONST))) &&
            payload.b != LIR_INVALID;
        // Range lowering owns two value slots: the source-visible binding and
        // a compiler-generated snapshot of the end bound. Prefix scanning the
        // per-HIR width keeps both in the same dense local family as ordinary
        // declarations without a serial allocation pass.
        bool range_for = core.kind == HIR_FOR_STMT ||
            (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR);
        semantic_local_flag[hir] = source_local ? 1u : range_for ? 2u : 0u;
        return;
    }
    semantic_local_flag[hir] = 0u;
}
