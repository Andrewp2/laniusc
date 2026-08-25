// Validates the least-summary fixed-point equation, replacement decisions,
// declaration preservation, and the reverse-user adjacency relation.

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
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
StructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_prefix;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_count;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_arguments;
StructuredBuffer<uint> opt_ir_ssa_block_argument_summary;
StructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint SUMMARY_NONE = 0u;
static const uint SUMMARY_CONFLICT = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint combine_summary(uint current, uint contribution)
{
    if (contribution == SUMMARY_NONE) return current;
    if (current == SUMMARY_NONE || current == contribution)
        return contribution;
    return SUMMARY_CONFLICT;
}

void report_structure_failure(uint row)
{
    {
        uint diagnostic_ignored;
        InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
            LOWERING_DIAGNOSTIC_NONE,
            LOWERING_DIAGNOSTIC_OPT_SSA_TRIVIAL_BLOCK_ARGUMENT_VALIDATE,
            diagnostic_ignored);
    }
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

    uint access_total = min(
        opt_ir_access_total[0u], gParams.access_capacity);
    uint incoming_total = min(
        opt_ir_ssa_block_argument_incoming_total[0u],
        gParams.incoming_capacity);
    uint user_total = min(
        opt_ir_ssa_block_argument_user_total[0u],
        gParams.demand_capacity * 2u);
    OptIrBlockArgument row = opt_ir_ssa_block_argument(argument);
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    bool valid = row.declaration < gParams.declaration_capacity &&
        row.incoming_start <= incoming_end &&
        incoming_end <= incoming_total;
    uint expected = SUMMARY_NONE;
    for (uint ordinal = 0u;
         valid && row.incoming_start + ordinal < incoming_end;
         ++ordinal)
    {
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[
                row.incoming_start + ordinal];
        OptIrSsaValueRef source =
            opt_ir_unpack_ssa_source(incoming.source);
        uint contribution = SUMMARY_NONE;
        if (valid && source.kind ==
                OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
        {
            valid = source.payload < access_total &&
                opt_ir_accesses[source.payload].subject ==
                    row.declaration;
            contribution = valid
                ? source.payload + 1u : SUMMARY_CONFLICT;
        }
        else if (valid && source.kind ==
                OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
        {
            valid = source.payload < argument_total &&
                opt_ir_ssa_block_argument(
                    source.payload).declaration == row.declaration;
            if (valid && source.payload != argument)
                contribution =
                    opt_ir_ssa_block_argument_summary[
                        source.payload];
        }
        else if (valid && source.kind == OPT_IR_SSA_SOURCE_INVALID)
            contribution = SUMMARY_CONFLICT;
        else
            valid = false;
        expected = combine_summary(expected, contribution);
    }
    uint summary = opt_ir_ssa_block_argument_summary[argument];
    valid = valid && summary == expected;

    OptIrSsaValueRef replacement = opt_ir_unpack_ssa_source(
        opt_ir_ssa_block_argument_replacement[argument]);
    if (summary != SUMMARY_NONE && summary != SUMMARY_CONFLICT)
        valid = valid &&
            replacement.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
            replacement.payload == summary - 1u;
    else
        valid = valid &&
            replacement.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            replacement.payload == argument;

    uint user_begin = opt_ir_ssa_block_argument_user_prefix[argument];
    uint user_end = argument + 1u < argument_total
        ? opt_ir_ssa_block_argument_user_prefix[argument + 1u]
        : user_total;
    valid = valid && user_begin <= user_end && user_end <= user_total &&
        opt_ir_ssa_block_argument_user_count[argument] ==
            user_end - user_begin;
    for (uint user_i = user_begin; valid && user_i < user_end; ++user_i)
    {
        uint user_argument =
            opt_ir_ssa_block_argument_user_arguments[user_i];
        valid = user_argument < argument_total &&
            user_argument != argument;
        if (valid)
        {
            OptIrBlockArgument user =
                opt_ir_ssa_block_argument(user_argument);
            uint user_incoming_end =
                opt_ir_ssa_block_argument_incoming_end(
                    user_argument, argument_total, incoming_total);
            valid = user.incoming_start <= user_incoming_end &&
                user_incoming_end <= incoming_total;
            bool found = false;
            for (uint ordinal = 0u;
                 valid && user.incoming_start + ordinal < user_incoming_end;
                 ++ordinal)
            {
                OptIrBlockArgumentIncoming incoming =
                    opt_ir_ssa_block_argument_incoming[
                        user.incoming_start + ordinal];
                OptIrSsaValueRef source =
                    opt_ir_unpack_ssa_source(incoming.source);
                found = found ||
                    (source.kind ==
                        OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
                     source.payload == argument);
            }
            valid = valid && found;
        }
    }

    if (!valid) report_structure_failure(argument);
}
