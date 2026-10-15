// Ordered after byte_count, before prefix scan, once per retained target page.
// byte_count owns every instruction body (through the shared instruction plan)
// and the prologue/footer. This pass adds the safety guard bytes.
import primitive_types;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.safety;
import codegen.lir.x86.location_common;
import gpu_index;
struct Params
{
    uint target_capacity; uint token_capacity; uint function_capacity; uint artifact_capacity;
    uint target_start; uint page_capacity; uint semantic_capacity; uint reserved1;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<X86LirLocations> target_lir_locations;
StructuredBuffer<uint> target_lir_flags;
RWStructuredBuffer<uint> target_byte_length;
RWStructuredBuffer<LoweringStatus> lowering_status;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    if (row >= min(gParams.target_capacity, target_lir_total[0u])) return;
    if ((target_lir_flags[page_row] & TARGET_LIR_FLAG_UNSUPPORTED) != 0u) return;
    X86LirCore core = target_lir_core[page_row];
    X86LirOperands operands = target_lir_operands[page_row];
    X86LirLocations locations = target_lir_locations[page_row];
    uint addition = x86_safety_guard_bytes(core, operands, locations);
    uint prior = target_byte_length[row];
    if (addition > gParams.artifact_capacity ||
        prior > gParams.artifact_capacity - addition)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_ARTIFACT_CAPACITY);
        return;
    }
    target_byte_length[row] = prior + addition;
}
