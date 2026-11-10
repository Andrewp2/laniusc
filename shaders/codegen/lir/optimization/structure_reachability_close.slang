// Closes the dead region below every dead root, one lane per block. Only the
// lane of a dead root does any work, so a program without dead blocks costs
// one load per block.
//
// A lane walks its region depth first. Each forward edge it leaves takes one
// from the target's count of live forward predecessors; the lane that takes
// the last one owns the target, marks it dead and descends into it. Exactly
// one lane owns each dead block, so no block is visited twice and no lane
// waits on another. The walk keeps no stack: a dead block records the edge
// that claimed it, and the lane returns along that edge to the next one.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrEdge> opt_ir_edges;
RWStructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_live_predecessor_count_by_block;
RWStructuredBuffer<uint> opt_ir_dead_claim_by_block;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint CLAIM_ROOT = 0xffffffffu;

void report_structure_failure(uint block)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REACHABILITY_CLOSE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u],
        gParams.block_capacity);
    if (root >= block_total) return;
    // Only this lane ever reads or writes the claim word of a dead root.
    if (opt_ir_dead_claim_by_block[root] != CLAIM_ROOT) return;
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);

    uint block = root;
    uint ordinal = 0u;
    // Every step either consumes one edge of the region or returns from one
    // block of it.
    uint budget = block_total + edge_total + 1u;
    for (uint step = 0u; step < budget; ++step)
    {
        OptIrBlock source = opt_ir_blocks[block];
        uint edge_start = opt_ir_block_edge_start(source);
        uint edge_count = opt_ir_block_edge_count(source);
        if (edge_start > edge_total ||
            edge_count > edge_total - min(edge_start, edge_total))
        {
            report_structure_failure(block);
            return;
        }
        if (ordinal < edge_count)
        {
            uint edge_id = edge_start + ordinal;
            ordinal += 1u;
            OptIrEdge edge = opt_ir_edges[edge_id];
            uint target = opt_ir_edge_to_block(edge.packed_target);
            if (edge.from_block != block || target >= block_total)
            {
                report_structure_failure(block);
                continue;
            }
            if ((opt_ir_edge_flags(edge.packed_target) & OPT_IR_EDGE_BACK) != 0u)
                continue;
            uint prior;
            InterlockedAdd(opt_ir_live_predecessor_count_by_block[target],
                0xffffffffu, prior);
            if (prior != 1u) continue;
            // This lane took the last live forward predecessor of the target.
            opt_ir_reachable[target] = 0u;
            opt_ir_dead_claim_by_block[target] = edge_id;
            block = target;
            ordinal = 0u;
            continue;
        }
        uint claim = opt_ir_dead_claim_by_block[block];
        if (claim == CLAIM_ROOT) return;
        if (claim >= edge_total)
        {
            report_structure_failure(block);
            return;
        }
        uint parent = opt_ir_edges[claim].from_block;
        if (parent >= block_total)
        {
            report_structure_failure(block);
            return;
        }
        uint parent_start = opt_ir_block_edge_start(opt_ir_blocks[parent]);
        if (claim < parent_start)
        {
            report_structure_failure(block);
            return;
        }
        ordinal = claim - parent_start + 1u;
        block = parent;
    }
    report_structure_failure(root);
}
