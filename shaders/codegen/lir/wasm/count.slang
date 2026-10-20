import codegen.lir.wasm.common;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;
import hir_records;

struct Params { uint semantic_capacity; uint semantic_start; uint page_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> semantic_lir_layout_word_offset;
StructuredBuffer<uint4> semantic_place_storage_by_token;
StructuredBuffer<uint> semantic_place_address_by_token;
StructuredBuffer<uint> wasm_frame_slots;
StructuredBuffer<uint> wasm_frame_bounds;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_param_value_layout;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
RWStructuredBuffer<uint> target_lir_count;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.semantic_start + page_row;
    uint count = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= count)
    {
        target_lir_count[row] = 0u;
        return;
    }
    WasmPlanRow plan = wasm_plan_row_at(row, count, semantic_lir_functions, semantic_schedule_order, opt_ir_core,
        opt_ir_operands, opt_ir_source_hir, semantic_function_id_by_hir, compact_hir_core,
        semantic_lir_layout_word_offset, semantic_place_storage_by_token,
        semantic_place_address_by_token, wasm_frame_slots, wasm_frame_bounds);
    target_lir_count[row] = wasm_plan_rows(plan, WASM_LIR_INVALID,
        semantic_lir_aggregate_elements, opt_ir_core,
        semantic_lir_params, semantic_param_value_layout);
}
