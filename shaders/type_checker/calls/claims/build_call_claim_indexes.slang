import type_checker.calls.inference_program;
import shared.collectives.step_program;
import type_checker.calls.claims.claim_index_steps;
import type_checker.calls.claims.call_environment_steps;

StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
RWStructuredBuffer<uint> call_generic_claim_lookup_head;
RWStructuredBuffer<uint> call_generic_claim_lookup_next;
RWStructuredBuffer<uint> call_generic_claim_slot_mask;

RWStructuredBuffer<uint> call_const_claim_lookup_head;
RWStructuredBuffer<uint> call_const_claim_lookup_next;
RWStructuredBuffer<uint> call_const_claim_slot_mask;
RWStructuredBuffer<uint> status;

struct ConstantClaimChain : IConstantClaimChain
{
    static uint head(uint bucket) { return call_const_claim_lookup_head[bucket]; }
    static uint next(uint row) { return call_const_claim_lookup_next[row]; }
};

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = begin_call_inference_program(group, local);
    uint generic_capacity; uint stride;
    call_generic_claim_callee.GetDimensions(generic_capacity, stride);
    uint generic_claims = min(call_generic_claim_count_out[0u], generic_capacity);
    uint constant_claims = constant_claim_count();
    // The two indexes have disjoint heads, links and masks.
    for (uint row = program.lane; row < max(generic_claims, constant_claims); row += program.lanes)
    {
        if (row < generic_claims)
            build_claim_lookup_row(row, generic_claims, call_generic_claim_callee,
                call_generic_claim_slot, call_generic_claim_lookup_head,
                call_generic_claim_lookup_next, call_generic_claim_slot_mask);
        if (row < constant_claims)
            build_claim_lookup_row(row, constant_claims, call_const_claim_callee,
                call_const_claim_slot, call_const_claim_lookup_head,
                call_const_claim_lookup_next, call_const_claim_slot_mask);
    }
    if (!call_inference_barrier(program, status)) return;
    for (uint row = program.lane; row < constant_claims; row += program.lanes)
        publish_call_environment_row<ConstantClaimChain>(row, constant_claims);
    step_program_end(program);
}
