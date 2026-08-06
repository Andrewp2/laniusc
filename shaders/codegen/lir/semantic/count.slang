import hir_records;
import codegen.lir.semantic.common;
import codegen.lir.semantic.loop_recipe;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_parent;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<uint> semantic_array_length;
StructuredBuffer<uint> semantic_iterable_kind;
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
    // Executable LIR belongs to a concrete checked function. Compact HIR also
    // contains path/name expressions used by module, import, type, and other
    // declaration syntax; those remain semantic metadata and must never be
    // scheduled as top-level machine instructions.
    if (node < count && semantic_function_id[node] != LIR_INVALID)
    {
        HirCore core = compact_hir_core[node];
        HirPayload payload = compact_hir_payload[node];
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
        bool for_loop = semantic_lir_is_for(core, payload);
        uint iterable_form = for_loop && payload.c < count
            ? compact_hir_payload[payload.c].a : 0u;
        uint iterable_kind = for_loop ? semantic_iterable_kind[node] : 0u;
        uint array_length = for_loop && payload.c < count
            ? semantic_array_length[payload.c] : 0xffffffffu;
        SemanticLoopRecipe recipe = semantic_loop_recipe(
            core, payload, iterable_form, iterable_kind, array_length);
        rows = owned_syntax ? 0u : recipe.row_count;
    }
    semantic_lir_count[node] = rows;
}
