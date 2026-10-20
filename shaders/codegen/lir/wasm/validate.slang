import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint target_start; uint page_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<WasmLirInstruction> target_lir_core;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> opt_ir_semantic_row;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint required = target_lir_total[0u];
    if (row == 0u && required > gParams.target_capacity)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_TARGET_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, required);
        InterlockedMin(lowering_status[0u].available_capacity, gParams.target_capacity);
    }
    if (row >= min(required, gParams.target_capacity)) return;
    WasmLirInstruction target = target_lir_core[page_row];
    if ((target.flags & TARGET_LIR_FLAG_UNSUPPORTED) == 0u) return;
    uint opt_row = target.semantic_instruction;
    bool has_opt_row = opt_row < gParams.semantic_capacity;
    uint hir = has_opt_row ? opt_ir_source_hir[opt_row] : 0xffffffffu;
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
    InterlockedMin(lowering_status[0u].first_unsupported_hir, hir);
    InterlockedMin(lowering_status[0u].first_unsupported_semantic_row,
        has_opt_row ? opt_ir_semantic_row[opt_row] : 0xffffffffu);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, opt_row);
    // Wasm opcodes of unsupported rows are placeholders, so the reported
    // opcode is the semantic LIR operation the backend could not lower.
    if (has_opt_row)
        InterlockedMin(lowering_status[0u].first_unsupported_target_op,
            opt_ir_op(opt_ir_core[opt_row]));
    // As on x86: keep a more specific earlier reason, otherwise publish a
    // source-addressable one so the host reports LNC0017 with a span.
    uint prior_reason;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_WASM_UNSUPPORTED_OPERATION,
        prior_reason);
    if (prior_reason == LOWERING_DIAGNOSTIC_NONE)
    {
        lowering_status[0u].diagnostic_detail_kind =
            LOWERING_DIAGNOSTIC_DETAIL_HIR;
        lowering_status[0u].diagnostic_detail = hir;
    }
}
