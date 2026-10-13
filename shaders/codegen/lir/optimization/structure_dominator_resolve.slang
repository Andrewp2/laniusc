// Resolve immediate dominators from the reachable CFG, in forward-dependency
// order. Each block has one writer. Joins intersect completed predecessor
// parent chains; lexical source owners do not determine dominance.
//
// The later edge validator proves that every omitted retreating edge targets
// a dominator of its source. Adding those edges therefore preserves the exact
// dominators computed on this acyclic graph.

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
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_forward_predecessor_count_by_block;
RWStructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<uint> opt_ir_reachability_work_state;
RWStructuredBuffer<uint> opt_ir_reachability_work_queue;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint WORKER_COUNT = 1u;
groupshared uint batch_begin;
groupshared uint batch_count;

void report_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.block_capacity;
}

uint common_parent(uint left, uint right, uint function_id, uint block_total)
{
    // A strictly decreasing position bounds each cursor by the block count.
    // Parent loads are atomic because earlier queue batches publish them in
    // this dispatch. No unresolved chain may be consumed.
    uint steps = 0u;
    while (left != right)
    {
        if (left >= block_total || right >= block_total ||
            opt_ir_blocks[left].function_id != function_id ||
            opt_ir_blocks[right].function_id != function_id ||
            steps >= block_total)
            return INVALID;
        bool advance_left = opt_ir_blocks[left].position_start >
            opt_ir_blocks[right].position_start;
        uint cursor = advance_left ? left : right;
        uint parent = ssa_atomic_load(opt_ir_immediate_dominator, cursor);
        if (parent >= block_total || parent == cursor ||
            opt_ir_blocks[parent].function_id != function_id ||
            opt_ir_blocks[parent].position_start >=
                opt_ir_blocks[cursor].position_start)
            return INVALID;
        if (advance_left) left = parent;
        else right = parent;
        steps += 1u;
    }
    return left;
}

void resolve_block(uint block, uint block_total, uint edge_total)
{
    if (block >= block_total || opt_ir_reachable[block] == 0u ||
        ssa_atomic_load(opt_ir_forward_predecessor_count_by_block, block) != 0u)
    {
        report_structure_failure(block);
        return;
    }
    OptIrBlock record = opt_ir_blocks[block];
    uint parent = ssa_atomic_load(opt_ir_immediate_dominator, block);
    if (parent != block)
    {
        if (parent != OPT_IR_DOMINATOR_UNRESOLVED)
        {
            report_structure_failure(block);
            return;
        }
        uint begin = opt_ir_predecessor_prefix[block];
        uint end = block + 1u < block_total
            ? opt_ir_predecessor_prefix[block + 1u] : edge_total;
        if (begin > end || end > edge_total)
        {
            report_structure_failure(block);
            return;
        }
        parent = INVALID;
        for (uint row = begin; row < end; ++row)
        {
            uint edge_id = opt_ir_predecessor_edge_ids[row];
            if (edge_id >= edge_total)
            {
                report_structure_failure(block);
                return;
            }
            OptIrEdge edge = opt_ir_edges[edge_id];
            uint predecessor = edge.from_block;
            if (predecessor >= block_total ||
                opt_ir_edge_to_block(edge.packed_target) != block)
            {
                report_structure_failure(block);
                return;
            }
            if ((opt_ir_edge_flags(edge.packed_target) & OPT_IR_EDGE_BACK) != 0u ||
                opt_ir_reachable[predecessor] == 0u)
                continue;
            if (opt_ir_blocks[predecessor].function_id != record.function_id ||
                opt_ir_blocks[predecessor].position_start >= record.position_start ||
                ssa_atomic_load(opt_ir_immediate_dominator, predecessor) >= block_total)
            {
                report_structure_failure(block);
                return;
            }
            parent = parent == INVALID ? predecessor
                : common_parent(parent, predecessor, record.function_id, block_total);
            if (parent == INVALID)
            {
                report_structure_failure(block);
                return;
            }
        }
        if (parent >= block_total ||
            opt_ir_blocks[parent].position_start >= record.position_start)
        {
            report_structure_failure(block);
            return;
        }
        uint ignored;
        InterlockedExchange(opt_ir_immediate_dominator[block], parent, ignored);
    }

    // Publish the completed parent before successor readiness is released.
    DeviceMemoryBarrier();
    uint begin = opt_ir_block_edge_start(record);
    uint count = opt_ir_block_edge_count(record);
    if (begin > edge_total || count > edge_total - min(begin, edge_total))
    {
        report_structure_failure(block);
        return;
    }
    for (uint ordinal = 0u; ordinal < count; ++ordinal)
    {
        OptIrEdge edge = opt_ir_edges[begin + ordinal];
        uint target = opt_ir_edge_to_block(edge.packed_target);
        if (edge.from_block != block || target >= block_total)
        {
            report_structure_failure(block);
            continue;
        }
        if ((opt_ir_edge_flags(edge.packed_target) & OPT_IR_EDGE_BACK) != 0u)
            continue;
        if (opt_ir_reachable[target] == 0u)
        {
            report_structure_failure(block);
            continue;
        }
        uint prior;
        InterlockedAdd(opt_ir_forward_predecessor_count_by_block[target],
            0xffffffffu, prior);
        if (prior == 0u)
        {
            report_structure_failure(target);
            continue;
        }
        if (prior != 1u) continue;
        uint required = 0u;
        if (!ssa_work_publish(target, gParams.block_capacity,
                opt_ir_reachability_work_state,
                opt_ir_reachability_work_queue, required))
            report_capacity(required);
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x >= WORKER_COUNT) return;
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
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
            resolve_block(ssa_work_read_published(opt_ir_reachability_work_queue,
                batch_begin + ltid.x), block_total, edge_total);
        GroupMemoryBarrierWithGroupSync();
        if (ltid.x == 0u)
            ssa_work_finish_batch(opt_ir_reachability_work_state, batch_count);
        GroupMemoryBarrierWithGroupSync();
    }
}
