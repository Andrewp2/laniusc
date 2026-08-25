// Canonicalizes predecessor sources through resolved demand aliases and counts
// reverse block-argument dependency rows. Self inputs remain in the incoming
// relation but do not create work-list edges.

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
    uint worker_count;
    uint max_radix_blocks;
    uint incoming_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<uint> opt_ir_ssa_demand_total;
StructuredBuffer<uint> opt_ir_ssa_demand_resolutions;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
RWStructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_user_count;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint argument = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint argument_total = min(
        opt_ir_ssa_block_argument_total[0u], gParams.demand_capacity);
    if (argument >= argument_total) return;

    uint incoming_total = min(
        opt_ir_ssa_block_argument_incoming_total[0u],
        gParams.incoming_capacity);
    uint access_total = min(
        opt_ir_access_total[0u], gParams.access_capacity);
    uint demand_total = min(
        opt_ir_ssa_demand_total[0u], gParams.demand_capacity);
    OptIrBlockArgument block_argument =
        opt_ir_ssa_block_arguments[argument];
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    bool valid = block_argument.incoming_start <= incoming_end &&
        incoming_end <= incoming_total;
    for (uint ordinal = 0u;
         valid && block_argument.incoming_start + ordinal < incoming_end;
         ++ordinal)
    {
        uint row = block_argument.incoming_start + ordinal;
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[row];
        OptIrSsaValueRef source =
            opt_ir_unpack_ssa_source(incoming.source);
        if (source.kind == OPT_IR_SSA_SOURCE_DEMAND)
        {
            valid = source.payload < demand_total;
            if (valid)
            {
                OptIrSsaValueRef resolved = opt_ir_unpack_ssa_source(
                    opt_ir_ssa_demand_resolutions[source.payload]);
                source = resolved;
                incoming.source = opt_ir_pack_ssa_source(source);
                opt_ir_ssa_block_argument_incoming[row] = incoming;
            }
        }

        valid = valid && (
            (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
                source.payload < access_total) ||
            (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
                source.payload < argument_total) ||
            (source.kind == OPT_IR_SSA_SOURCE_INVALID &&
                source.payload == INVALID));
        if (!valid)
        {
            report_structure_failure(row);
            return;
        }

        if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            source.payload != argument)
            InterlockedAdd(
                opt_ir_ssa_block_argument_user_count[
                    source.payload],
                1u);
    }
}
