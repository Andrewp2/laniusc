import codegen.lir.wasm.common;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;
import native_value_layout;

// Publishes each function's frame word range and each slot's word 0, after
// the exclusive scan of wasm_frame_words. A header ADDRESS of a parameter
// also records the parameter's checked type: its home is filled on entry. An
// argument view's descriptor takes the row's top three words.
struct Params { uint semantic_capacity; uint n_tokens; uint function_capacity; uint call_arg_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<uint> wasm_frame_words;
StructuredBuffer<uint> wasm_frame_prefix;
RWStructuredBuffer<uint> wasm_frame_slots;
RWStructuredBuffer<uint> wasm_frame_bounds;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint function_of(uint row)
{
    return semantic_function_id_by_hir[opt_ir_source_hir[semantic_schedule_order[row]]];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= count) return;
    uint semantic_row = semantic_schedule_order[row];
    uint function_id = function_of(row);
    uint words = wasm_frame_words[row];
    uint prefix = wasm_frame_prefix[row];
    uint base = WASM_FRAME_SLOT_STRIDE * semantic_row;
    bool view = wasm_frame_slots[base + 3u] != WASM_LIR_INVALID;
    uint own_words = view ? words - NATIVE_SLICE_WORDS : words;
    uint param_type = WASM_LIR_INVALID;
    if (opt_ir_op(opt_ir_core[semantic_row]) == SEMANTIC_LIR_OP_ADDRESS && own_words != 0u &&
        function_id < gParams.function_capacity)
    {
        SemanticLirFunction function = semantic_lir_functions[function_id];
        uint ordinal = semantic_row - semantic_lir_offset[function.hir_function];
        if (ordinal < function.param_count)
            param_type = semantic_lir_params[function.param_start + ordinal].type_id;
    }
    wasm_frame_slots[base] = own_words == 0u ? WASM_LIR_INVALID : prefix + own_words - 1u;
    wasm_frame_slots[base + 1u] = param_type;
    wasm_frame_slots[base + 2u] = view ? prefix + words - 1u : WASM_LIR_INVALID;
    if (function_id >= gParams.function_capacity) return;
    if (row == 0u || function_of(row - 1u) != function_id)
        wasm_frame_bounds[2u * function_id] = prefix;
    if (row + 1u == count || function_of(row + 1u) != function_id)
        wasm_frame_bounds[2u * function_id + 1u] = prefix + words;
}
