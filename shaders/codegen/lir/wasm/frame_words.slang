import codegen.lir.wasm.common;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;
import native_value_layout;
import hir_records;

// Frame words each scheduled row owns in its function's shadow-stack frame
// (docs/wasm-memory-layout.md). An exclusive scan of these words places every
// slot; functions are contiguous in schedule order. A fixed array passed as a
// slice also owns the three words of its view descriptor, whose length is
// published for the later passes.
struct Params { uint semantic_capacity; uint n_tokens; uint function_capacity; uint call_arg_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint4> semantic_place_storage_by_token;
StructuredBuffer<uint> semantic_lir_call_arg_total;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> wasm_frame_view_hint;
RWStructuredBuffer<uint> wasm_frame_words;
RWStructuredBuffer<uint> wasm_frame_slots;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.semantic_capacity) return;
    uint count = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= count)
    {
        wasm_frame_words[row] = 0u;
        return;
    }
    uint semantic_row = semantic_schedule_order[row];
    OptIrNodeCore core = opt_ir_core[semantic_row];
    OptIrNodeOperands operands = opt_ir_operands[semantic_row];
    bool home_row = wasm_home_row(semantic_row, opt_ir_core, opt_ir_source_hir, compact_hir_core);
    uint4 storage = home_row && operands.a < gParams.n_tokens
        ? semantic_place_storage_by_token[operands.a] : uint4(0u, 0u, 0u, 0u);
    uint value_op = operands.b < count ? opt_ir_op(opt_ir_core[operands.b]) : SEMANTIC_LIR_OP_INVALID;
    bool discarded = wasm_discarded_result_values(core,
        wasm_statement_call(compact_hir_core, opt_ir_source_hir[semantic_row])) != 0u;
    uint hint = wasm_frame_view_hint[semantic_row];
    uint view_length = WASM_LIR_INVALID;
    if (hint < min(gParams.call_arg_capacity, semantic_lir_call_arg_total[0u]) &&
        semantic_lir_call_args[hint].value_instruction == semantic_row)
        view_length = wasm_argument_view_length(semantic_lir_call_args[hint], core,
                                                opt_ir_core, count);
    wasm_frame_slots[WASM_FRAME_SLOT_STRIDE * semantic_row + 3u] = view_length;
    wasm_frame_words[row] = wasm_row_frame_words(core, operands, home_row, storage,
                                                 value_op, discarded) +
        (view_length != WASM_LIR_INVALID ? NATIVE_SLICE_WORDS : 0u);
}
