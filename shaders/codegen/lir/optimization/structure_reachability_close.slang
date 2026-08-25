// Computes exact CFG reachability with persistent, batched GPU workers. Work
// is linear in reachable blocks and edges and independent of CFG depth.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;

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
RWStructuredBuffer<uint> opt_ir_reachability_work_state;
RWStructuredBuffer<uint> opt_ir_reachability_work_queue;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint WORKER_COUNT = 32u;

groupshared uint batch_begin;
groupshared uint batch_count;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.block_capacity;
}

void report_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x >= WORKER_COUNT) return;
    uint block_total = min(opt_ir_block_total[0u],
        gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u],
        gParams.edge_capacity);

    for (;;)
    {
        if (ltid.x == 0u)
            ssa_work_try_pop_batch(gParams.block_capacity, 32u,
                opt_ir_reachability_work_state, batch_begin, batch_count);
        GroupMemoryBarrierWithGroupSync();
        if (batch_count == 0u)
        {
            if (ssa_work_quiescent(opt_ir_reachability_work_state)) return;
            continue;
        }

        if (ltid.x < batch_count)
        {
            uint block = ssa_work_read_published(
                opt_ir_reachability_work_queue,
                batch_begin + ltid.x);
            if (block >= block_total || opt_ir_reachable[block] == 0u)
                report_structure_failure(block);
            else
            {
                OptIrBlock source = opt_ir_blocks[block];
                uint edge_start = opt_ir_block_edge_start(source);
                uint edge_count = opt_ir_block_edge_count(source);
                if (edge_start > edge_total ||
                    edge_count > edge_total - min(edge_start, edge_total))
                    report_structure_failure(block);
                else
                {
                    for (uint ordinal = 0u; ordinal < edge_count; ++ordinal)
                    {
                        OptIrEdge edge = opt_ir_edges[edge_start + ordinal];
                        uint target = opt_ir_edge_to_block(edge.packed_target);
                        if (edge.from_block != block || target >= block_total)
                        {
                            report_structure_failure(block);
                            continue;
                        }
                        uint prior;
                        InterlockedCompareExchange(
                            opt_ir_reachable[target], 0u, 1u, prior);
                        if (prior != 0u) continue;
                        uint required = 0u;
                        if (!ssa_work_publish(target, gParams.block_capacity,
                                opt_ir_reachability_work_state,
                                opt_ir_reachability_work_queue, required))
                            report_capacity(required);
                    }
                }
            }
        }

        GroupMemoryBarrierWithGroupSync();
        if (ltid.x == 0u)
            ssa_work_finish_batch(
                opt_ir_reachability_work_state, batch_count);
        GroupMemoryBarrierWithGroupSync();
    }
}
