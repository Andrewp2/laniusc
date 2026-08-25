// Computes the sparse backward block-entry-demand closure without host
// iteration. Persistent workgroups consume one global queue; exact atomic
// admission ensures each `(declaration, block)` row is materialized once.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_lookup;
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
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_ssa_demand_total;
RWStructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
RWStructuredBuffer<uint> opt_ir_ssa_sparse_declaration;
RWStructuredBuffer<uint> opt_ir_ssa_sparse_block;
RWStructuredBuffer<uint> opt_ir_ssa_work_state;
RWStructuredBuffer<uint> opt_ir_ssa_work_queue;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;

groupshared uint batch_begin;
groupshared uint batch_count;

void report_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
}

void report_structure_failure(uint row, uint reason)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, reason, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

void admit_predecessor(uint declaration, uint block)
{
    uint hash_capacity = gParams.demand_capacity * 2u + 1u;
    uint hash_slot = 0xffffffffu;
    uint result = ssa_sparse_insert_key(
        declaration,
        block,
        hash_capacity,
        opt_ir_ssa_sparse_declaration,
        opt_ir_ssa_sparse_block,
        hash_slot);
    if (result == SSA_SPARSE_INSERT_EXISTING) return;
    if (result == SSA_SPARSE_INSERT_FULL)
    {
        report_capacity(hash_capacity + 1u, hash_capacity);
        return;
    }

    uint row;
    InterlockedAdd(opt_ir_ssa_demand_total[0u], 1u, row);
    if (row >= gParams.demand_capacity)
    {
        report_capacity(row + 1u, gParams.demand_capacity);
        return;
    }
    OptIrSsaDemand demand;
    demand.declaration = declaration;
    demand.block = block;
    opt_ir_ssa_demands[row] = demand;
    uint required = 0u;
    uint queue_capacity = gParams.demand_capacity * 2u;
    if (!ssa_work_publish(
            hash_slot,
            queue_capacity,
            opt_ir_ssa_work_state,
            opt_ir_ssa_work_queue,
            required))
        report_capacity(required, queue_capacity);
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x >= gParams.worker_count) return;

    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint access_total = opt_ir_active_access_total(gParams.access_capacity);
    uint declaration_block_total = opt_ir_active_declaration_block_total(
        gParams.declaration_block_capacity);
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
            uint source_row = ssa_work_read_published(
                opt_ir_ssa_work_queue, batch_begin + ltid.x);
            uint hash_capacity = gParams.demand_capacity * 2u + 1u;
            uint declaration_key = source_row < hash_capacity
                ? ssa_atomic_load(opt_ir_ssa_sparse_declaration, source_row)
                : 0u;
            uint block_key = source_row < hash_capacity
                ? ssa_atomic_load(opt_ir_ssa_sparse_block, source_row)
                : 0u;
            if (source_row >= hash_capacity ||
                declaration_key == 0u || block_key == 0u)
            {
                report_structure_failure(source_row, 1021u);
            }
            else
            {
                OptIrSsaDemand source;
                source.declaration = declaration_key - 1u;
                source.block = block_key - 1u;
                uint predecessor_start = source.block < block_total
                    ? opt_ir_predecessor_prefix[source.block]
                    : edge_total + 1u;
                uint predecessor_end = source.block + 1u < block_total
                    ? opt_ir_predecessor_prefix[source.block + 1u]
                    : edge_total;
                if (source.block >= block_total ||
                    predecessor_start > predecessor_end ||
                    predecessor_end > edge_total)
                {
                    report_structure_failure(source_row, 1022u);
                }
                else
                {
                    for (uint predecessor_i = predecessor_start;
                         predecessor_i < predecessor_end;
                         ++predecessor_i)
                    {
                        uint edge_id = opt_ir_predecessor_edge_ids[
                            predecessor_i];
                        if (edge_id >= edge_total)
                        {
                            report_structure_failure(source_row, 1023u);
                            continue;
                        }
                        OptIrEdge edge = opt_ir_edges[edge_id];
                        uint predecessor = edge.from_block;
                        if (opt_ir_edge_to_block(edge.packed_target) !=
                                source.block ||
                            predecessor >= block_total)
                        {
                            report_structure_failure(source_row, 1024u);
                            continue;
                        }
                        if (opt_ir_reachable[predecessor] == 0u)
                            continue;
                        if (opt_ir_outgoing_local_definition(
                                source.declaration,
                                predecessor,
                                declaration_block_total,
                                access_total) == INVALID)
                            admit_predecessor(
                                source.declaration, predecessor);
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
