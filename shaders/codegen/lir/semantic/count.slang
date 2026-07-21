import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_parent;
RWStructuredBuffer<uint> semantic_lir_count;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= gParams.n_hir_nodes) return;
    uint rows = 0u;
    if (node < count)
    {
        uint parent = compact_expr_parent[node];
        bool owned_syntax = parent < count &&
            ((compact_hir_core[parent].kind == HIR_CALL_EXPR &&
              compact_hir_payload[parent].a == node) ||
             ((compact_hir_core[parent].kind == HIR_STMT ||
               compact_hir_core[parent].kind == HIR_ASSIGN_EXPR) &&
              compact_hir_payload[parent].a == HIR_STMT_ASSIGN &&
              compact_hir_payload[parent].b == node) ||
             ((compact_hir_core[parent].kind == HIR_FOR_STMT ||
               (compact_hir_core[parent].kind == HIR_STMT &&
                compact_hir_payload[parent].a == HIR_STMT_FOR)) &&
              compact_hir_payload[parent].c == node));
        HirCore core = compact_hir_core[node];
        HirPayload payload = compact_hir_payload[node];
        bool range_for = core.kind == HIR_FOR_STMT ||
            (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR);
        uint iterable_form = range_for && payload.c < count
            ? compact_hir_payload[payload.c].a : 0u;
        rows = owned_syntax ? 0u : range_for
            ? (iterable_form == HIR_EXPR_RANGE || iterable_form == HIR_EXPR_RANGE_INCLUSIVE
                ? 17u : 1u)
            : semantic_lir_row_count(core, payload);
    }
    semantic_lir_count[node] = rows;
}
