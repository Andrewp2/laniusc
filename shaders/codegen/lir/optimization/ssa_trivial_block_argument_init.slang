// Initializes the least-summary lattice and marks the arguments whose direct
// sources already give them a summary: each is the root of one propagation
// lane.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_block_argument_lookup;
import gpu_index;

struct Params
{
    uint block_capacity;
    uint edge_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint declaration_block_capacity;
    uint demand_capacity;
    uint reserved0;
    uint max_radix_blocks;
    uint incoming_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
StructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_summary;
RWStructuredBuffer<uint> opt_ir_ssa_walk;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint SUMMARY_NONE = 0u;
static const uint SUMMARY_CONFLICT = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
// The first walk word of each of an argument's two transitions (to one
// source, to conflict): whether the transition is this argument's own start.
static const uint WALK_ROOT = 0xffffffffu;
static const uint WALK_UNCLAIMED = 0xfffffffeu;

uint combine_summary(uint current, uint contribution)
{
    if (contribution == SUMMARY_NONE) return current;
    if (current == SUMMARY_NONE || current == contribution)
        return contribution;
    return SUMMARY_CONFLICT;
}

uint direct_summary(OptIrBlockArgumentIncoming incoming)
{
    OptIrSsaValueRef source = opt_ir_unpack_ssa_source(incoming.source);
    if (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
        return source.payload + 1u;
    if (source.kind == OPT_IR_SSA_SOURCE_INVALID)
        return SUMMARY_CONFLICT;
    return SUMMARY_NONE;
}

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, 103u, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint argument = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint argument_total = opt_ir_active_ssa_block_argument_total(
        gParams.demand_capacity);
    if (argument >= argument_total) return;

    uint incoming_total = min(
        opt_ir_ssa_block_argument_incoming_total[0u],
        gParams.incoming_capacity);
    OptIrBlockArgument row = opt_ir_ssa_block_argument(argument);
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    bool valid = row.declaration < gParams.declaration_capacity &&
        row.incoming_start <= incoming_end &&
        incoming_end <= incoming_total;
    uint summary = valid ? SUMMARY_NONE : SUMMARY_CONFLICT;
    for (uint ordinal = 0u;
         valid && row.incoming_start + ordinal < incoming_end;
         ++ordinal)
        summary = combine_summary(
            summary,
            direct_summary(opt_ir_ssa_block_argument_incoming[
                row.incoming_start + ordinal]));
    opt_ir_ssa_block_argument_summary[argument] = summary;
    if (!valid) report_structure_failure(argument);

    uint transition = 2u * argument;
    opt_ir_ssa_walk[2u * transition] =
        summary != SUMMARY_NONE && summary != SUMMARY_CONFLICT
            ? WALK_ROOT : WALK_UNCLAIMED;
    opt_ir_ssa_walk[2u * (transition + 1u)] =
        summary == SUMMARY_CONFLICT ? WALK_ROOT : WALK_UNCLAIMED;
}
