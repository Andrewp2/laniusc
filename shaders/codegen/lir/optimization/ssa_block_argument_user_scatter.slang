// Scatters consuming block-argument IDs into source adjacency ranges.

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
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
StructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_prefix;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_total;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_user_count;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_user_arguments;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

void report_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
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
    uint user_capacity = gParams.demand_capacity * 2u;
    uint raw_user_total = opt_ir_ssa_block_argument_user_total[0u];
    if (argument == 0u && raw_user_total > user_capacity)
        report_capacity(raw_user_total, user_capacity);
    uint user_total = min(raw_user_total, user_capacity);
    OptIrBlockArgument block_argument =
        opt_ir_ssa_block_arguments[argument];
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    if (block_argument.incoming_start > incoming_end ||
        incoming_end > incoming_total)
    {
        report_structure_failure(argument);
        return;
    }

    for (uint ordinal = 0u;
         block_argument.incoming_start + ordinal < incoming_end;
         ++ordinal)
    {
        uint row = block_argument.incoming_start + ordinal;
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[row];
        OptIrSsaValueRef source =
            opt_ir_unpack_ssa_source(incoming.source);
        if (source.kind != OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT ||
            source.payload == argument)
            continue;
        if (source.payload >= argument_total)
        {
            report_structure_failure(row);
            continue;
        }

        uint user_ordinal;
        InterlockedAdd(
            opt_ir_ssa_block_argument_user_count[source.payload],
            1u,
            user_ordinal);
        uint target = opt_ir_ssa_block_argument_user_prefix[
            source.payload] + user_ordinal;
        if (target < user_total)
            opt_ir_ssa_block_argument_user_arguments[target] = argument;
        else
            report_structure_failure(row);
    }
}
