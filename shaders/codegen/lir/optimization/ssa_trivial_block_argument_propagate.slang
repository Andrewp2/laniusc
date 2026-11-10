// Propagates least summaries through reverse block-argument users, one lane
// per argument whose direct sources give it a summary. An argument changes at
// most twice (none, one source, conflict). The lane whose compare-exchange
// makes a change owns that transition and carries it on to the argument's own
// users, so every change reaches every user and no lane waits on another.
//
// The walk keeps no stack: a transition records the transition that caused it
// and that one's next user row, and the lane returns along that record.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_block_argument_lookup;
import codegen.lir.optimization.ssa_sparse_work;
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
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_prefix;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_user_arguments;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_summary;
// Two words per transition `2 * argument + level`: the transition that caused
// it, then that transition's next user row.
RWStructuredBuffer<uint> opt_ir_ssa_walk;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint SUMMARY_NONE = 0u;
static const uint SUMMARY_CONFLICT = 0xffffffffu;

static const uint INVALID = 0xffffffffu;
static const uint WALK_ROOT = 0xffffffffu;
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
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, 104u, ignored);
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
    // A transition that is a root is never claimed, so its mark is stable; any
    // other first word is either unclaimed or another lane's record.
    uint root = INVALID;
    if (opt_ir_ssa_walk[4u * argument] == WALK_ROOT)
        root = 2u * argument;
    else if (opt_ir_ssa_walk[4u * argument + 2u] == WALK_ROOT)
        root = 2u * argument + 1u;
    if (root == INVALID) return;
    uint user_total = min(
        opt_ir_ssa_block_argument_user_total[0u],
        gParams.demand_capacity * 2u);

    uint transition = root;
    uint cursor = opt_ir_ssa_block_argument_user_prefix[argument];
    // A lane enters each transition it owns once and returns from it once.
    uint budget = 4u * argument_total + 2u;
    for (uint step = 0u; step < budget; ++step)
    {
        uint source = transition >> 1u;
        // Summary updates happen in other workgroups. Read through the same
        // atomic coherence domain as the compare-exchange writers; a later
        // value than this transition's own is still a sound contribution.
        uint contribution = ssa_atomic_load(
            opt_ir_ssa_block_argument_summary, source);
        uint user_end = source + 1u < argument_total
            ? opt_ir_ssa_block_argument_user_prefix[source + 1u]
            : user_total;
        if (cursor > user_end || user_end > user_total)
        {
            report_structure_failure(source);
            cursor = user_end;
        }
        uint claimed = INVALID;
        while (cursor < user_end && claimed == INVALID)
        {
            uint user = opt_ir_ssa_block_argument_user_arguments[cursor];
            cursor += 1u;
            if (user >= argument_total ||
                opt_ir_ssa_block_argument(user).declaration !=
                    opt_ir_ssa_block_argument(source).declaration)
            {
                report_structure_failure(user);
                continue;
            }
            uint observed = ssa_atomic_load(
                opt_ir_ssa_block_argument_summary, user);
            // The user changes at most twice, so the exchange settles.
            for (uint attempt = 0u; attempt < 4u; ++attempt)
            {
                uint combined = combine_summary(observed, contribution);
                if (combined == observed) break;
                uint prior;
                InterlockedCompareExchange(
                    opt_ir_ssa_block_argument_summary[user],
                    observed,
                    combined,
                    prior);
                if (prior == observed)
                {
                    claimed = 2u * user +
                        (combined == SUMMARY_CONFLICT ? 1u : 0u);
                    break;
                }
                observed = prior;
            }
        }
        if (claimed != INVALID)
        {
            opt_ir_ssa_walk[2u * claimed] = transition;
            opt_ir_ssa_walk[2u * claimed + 1u] = cursor;
            transition = claimed;
            cursor = opt_ir_ssa_block_argument_user_prefix[claimed >> 1u];
            continue;
        }
        if (transition == root) return;
        cursor = opt_ir_ssa_walk[2u * transition + 1u];
        transition = opt_ir_ssa_walk[2u * transition];
    }
}
