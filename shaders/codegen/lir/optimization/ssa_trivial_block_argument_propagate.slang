// Propagates least summaries through reverse block-argument users using one
// global bounded queue. Each argument changes at most twice.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_block_argument_lookup;
import codegen.lir.optimization.ssa_sparse_work;

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
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_prefix;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_arguments;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_summary;
RWStructuredBuffer<uint> opt_ir_ssa_work_state;
RWStructuredBuffer<uint> opt_ir_ssa_work_queue;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint SUMMARY_NONE = 0u;
static const uint SUMMARY_CONFLICT = 0xffffffffu;

groupshared uint batch_begin;
groupshared uint batch_count;

uint combine_summary(uint current, uint contribution)
{
    if (contribution == SUMMARY_NONE) return current;
    if (current == SUMMARY_NONE || current == contribution)
        return contribution;
    return SUMMARY_CONFLICT;
}

void report_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
}

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, 104u, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

void contribute_to_user(
    uint source,
    uint user,
    uint contribution,
    uint argument_total)
{
    if (user >= argument_total ||
        opt_ir_ssa_block_argument(user).declaration !=
            opt_ir_ssa_block_argument(source).declaration)
    {
        report_structure_failure(user);
        return;
    }

    uint observed = opt_ir_ssa_block_argument_summary[user];
    for (;;)
    {
        uint combined = combine_summary(observed, contribution);
        if (combined == observed) return;
        uint prior;
        InterlockedCompareExchange(
            opt_ir_ssa_block_argument_summary[user],
            observed,
            combined,
            prior);
        if (prior == observed)
        {
            uint required = 0u;
            uint queue_capacity = gParams.demand_capacity * 2u;
            if (!ssa_work_publish(
                    user,
                    queue_capacity,
                    opt_ir_ssa_work_state,
                    opt_ir_ssa_work_queue,
                    required))
                report_capacity(required, queue_capacity);
            return;
        }
        observed = prior;
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x >= gParams.worker_count) return;
    uint argument_total = opt_ir_active_ssa_block_argument_total(
        gParams.demand_capacity);
    uint user_total = min(
        opt_ir_ssa_block_argument_user_total[0u],
        gParams.demand_capacity * 2u);
    uint queue_capacity = gParams.demand_capacity * 2u;

    for (;;)
    {
        if (ltid.x == 0u)
            ssa_work_try_pop_batch(
                queue_capacity,
                32u,
                opt_ir_ssa_work_state,
                batch_begin,
                batch_count);
        GroupMemoryBarrierWithGroupSync();
        if (batch_count == 0u)
        {
            if (ssa_work_quiescent(opt_ir_ssa_work_state)) return;
            continue;
        }

        if (ltid.x < batch_count)
        {
            uint source_argument = ssa_work_read_published(
                opt_ir_ssa_work_queue, batch_begin + ltid.x);
            if (source_argument >= argument_total)
            {
                report_structure_failure(source_argument);
            }
            else
            {
                // Summary updates and queue publication happen in different
                // workgroups. Read through the same atomic coherence domain as
                // the compare-exchange writers so a queued re-publication
                // cannot propagate an older lattice value.
                uint contribution = ssa_atomic_load(
                    opt_ir_ssa_block_argument_summary,
                    source_argument);
                uint user_begin =
                    opt_ir_ssa_block_argument_user_prefix[source_argument];
                uint user_end = source_argument + 1u < argument_total
                    ? opt_ir_ssa_block_argument_user_prefix[
                        source_argument + 1u]
                    : user_total;
                if (user_begin > user_end || user_end > user_total)
                {
                    report_structure_failure(source_argument);
                }
                else
                {
                    for (uint user_i = user_begin;
                         user_i < user_end;
                         ++user_i)
                    {
                        uint user_argument =
                            opt_ir_ssa_block_argument_user_arguments[user_i];
                        contribute_to_user(
                            source_argument,
                            user_argument,
                            contribution,
                            argument_total);
                    }
                }
            }
        }

        GroupMemoryBarrierWithGroupSync();
        if (ltid.x == 0u)
            ssa_work_finish_batch(
                opt_ir_ssa_work_state, batch_count);
        GroupMemoryBarrierWithGroupSync();
    }
}
