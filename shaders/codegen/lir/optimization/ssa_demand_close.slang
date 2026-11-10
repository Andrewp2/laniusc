// Computes the sparse backward block-entry-demand closure without host
// iteration, one lane per seed demand. A lane walks backward from its seed
// through the reachable predecessors that do not define the declaration.
// Exact atomic admission materializes each `(declaration, block)` row once,
// and the lane that admits a row owns it and walks on from it, so no lane
// waits on another.
//
// The walk keeps no stack: a closure row records the predecessor row it was
// admitted through and the demand that admitted it, and the lane returns along
// that record.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_lookup;
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
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<uint> opt_ir_reachable;
StructuredBuffer<uint> opt_ir_ssa_demand_seed_total;
RWStructuredBuffer<uint> opt_ir_ssa_demand_total;
RWStructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
RWStructuredBuffer<uint> opt_ir_ssa_sparse_declaration;
RWStructuredBuffer<uint> opt_ir_ssa_sparse_block;
// Two words per closure row: the predecessor row it was admitted through, then
// the demand row that admitted it.
RWStructuredBuffer<uint> opt_ir_ssa_walk;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint seed_total = min(
        opt_ir_ssa_demand_seed_total[0u], gParams.demand_capacity);
    if (root_row >= seed_total) return;

    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint access_total = opt_ir_active_access_total(gParams.access_capacity);
    uint declaration_block_total = opt_ir_active_declaration_block_total(
        gParams.declaration_block_capacity);
    uint hash_capacity = gParams.demand_capacity * 2u + 1u;

    // Seed rows are final; closure rows are appended after them.
    OptIrSsaDemand root = opt_ir_ssa_demands[root_row];
    uint declaration = root.declaration;
    // The lane never leaves its declaration, so it narrows the definition
    // lookup to that declaration's rows once.
    uint window_start = 0u;
    uint window_end = declaration_block_total;
    for (uint side = 0u; side < 2u; ++side)
    {
        uint bound = opt_ir_lower_bound_declaration_block_in(
            declaration,
            side == 0u ? 0u : INVALID,
            window_start,
            declaration_block_total,
            access_total);
        if (side == 0u) window_start = bound;
        else window_end = bound;
    }
    uint row = root_row;
    uint block = root.block;
    uint cursor = block < block_total
        ? opt_ir_predecessor_prefix[block] : INVALID;
    // A lane enters each row it owns once and returns from it once.
    uint budget = 2u * gParams.demand_capacity + 2u;
    for (uint step = 0u; step < budget; ++step)
    {
        uint predecessor_end = block + 1u < block_total
            ? opt_ir_predecessor_prefix[block + 1u] : edge_total;
        if (block >= block_total || cursor > predecessor_end ||
            predecessor_end > edge_total)
        {
            report_structure_failure(row, 1022u);
            cursor = predecessor_end;
        }
        bool admitted = false;
        while (cursor < predecessor_end && !admitted)
        {
            uint predecessor_row = cursor;
            cursor += 1u;
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_row];
            if (edge_id >= edge_total)
            {
                report_structure_failure(row, 1023u);
                continue;
            }
            OptIrEdge edge = opt_ir_edges[edge_id];
            uint predecessor = edge.from_block;
            if (opt_ir_edge_to_block(edge.packed_target) != block ||
                predecessor >= block_total)
            {
                report_structure_failure(row, 1024u);
                continue;
            }
            if (opt_ir_reachable[predecessor] == 0u) continue;
            if (opt_ir_outgoing_local_definition_in(
                    declaration,
                    predecessor,
                    window_start,
                    window_end,
                    declaration_block_total,
                    access_total) != INVALID)
                continue;

            uint hash_slot = INVALID;
            uint result = ssa_sparse_insert_key(
                declaration,
                predecessor,
                hash_capacity,
                opt_ir_ssa_sparse_declaration,
                opt_ir_ssa_sparse_block,
                hash_slot);
            if (result == SSA_SPARSE_INSERT_EXISTING) continue;
            if (result == SSA_SPARSE_INSERT_FULL)
            {
                report_capacity(hash_capacity + 1u, hash_capacity);
                continue;
            }
            uint admitted_row;
            InterlockedAdd(opt_ir_ssa_demand_total[0u], 1u, admitted_row);
            if (admitted_row >= gParams.demand_capacity)
            {
                report_capacity(admitted_row + 1u, gParams.demand_capacity);
                continue;
            }
            OptIrSsaDemand demand;
            demand.declaration = declaration;
            demand.block = predecessor;
            opt_ir_ssa_demands[admitted_row] = demand;
            opt_ir_ssa_walk[2u * admitted_row] = predecessor_row;
            opt_ir_ssa_walk[2u * admitted_row + 1u] = row;
            row = admitted_row;
            block = predecessor;
            cursor = opt_ir_predecessor_prefix[predecessor];
            admitted = true;
        }
        if (admitted) continue;
        if (row == root_row) return;
        // The record was checked when this lane admitted the row through it.
        uint predecessor_row = opt_ir_ssa_walk[2u * row];
        row = opt_ir_ssa_walk[2u * row + 1u];
        block = opt_ir_edge_to_block(opt_ir_edges[
            opt_ir_predecessor_edge_ids[predecessor_row]].packed_target);
        cursor = predecessor_row + 1u;
    }
}
