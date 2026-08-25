// Materializes one pruned block argument per demanded join and one symbolic
// source per predecessor. Non-join demands resolve directly to their sole
// predecessor source (or remain explicitly invalid at a CFG entry).

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_lookup;
import codegen.lir.optimization.ssa_demand_canonical_lookup;
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
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<uint> opt_ir_reachable;
StructuredBuffer<uint> opt_ir_ssa_block_argument_prefix;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
RWStructuredBuffer<uint> opt_ir_ssa_demand_resolutions;
RWStructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
RWStructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
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

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

OptIrSsaValueRef predecessor_source(
    uint declaration,
    uint predecessor,
    uint demand_total,
    uint declaration_block_total,
    uint access_total)
{
    OptIrSsaValueRef source;
    uint definition = opt_ir_outgoing_local_definition(
        declaration,
        predecessor,
        declaration_block_total,
        access_total);
    if (definition != INVALID)
    {
        source.kind = OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        source.payload = definition;
        return source;
    }
    source.kind = OPT_IR_SSA_SOURCE_DEMAND;
    source.payload = opt_ir_find_ssa_demand(
        declaration, predecessor, demand_total);
    if (source.payload == INVALID) source.kind = OPT_IR_SSA_SOURCE_INVALID;
    return source;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = opt_ir_active_ssa_demand_total(gParams.demand_capacity);
    if (row >= total) return;

    uint raw_argument_total = opt_ir_ssa_block_argument_total[0u];
    uint raw_incoming_total = opt_ir_ssa_block_argument_incoming_total[0u];
    if (row == 0u)
    {
        if (raw_argument_total > gParams.demand_capacity)
            report_capacity(raw_argument_total, gParams.demand_capacity);
        if (raw_incoming_total > gParams.incoming_capacity)
            report_capacity(raw_incoming_total, gParams.incoming_capacity);
    }
    uint argument_total = min(raw_argument_total, gParams.demand_capacity);
    uint incoming_total = min(raw_incoming_total, gParams.incoming_capacity);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint access_total = opt_ir_active_access_total(gParams.access_capacity);
    uint declaration_block_total = opt_ir_active_declaration_block_total(
        gParams.declaration_block_capacity);
    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    if (demand.block >= block_total)
    {
        report_structure_failure(row);
        return;
    }
    uint predecessor_start = opt_ir_predecessor_prefix[demand.block];
    uint predecessor_end = demand.block + 1u < block_total
        ? opt_ir_predecessor_prefix[demand.block + 1u]
        : edge_total;
    if (predecessor_start > predecessor_end || predecessor_end > edge_total)
    {
        report_structure_failure(row);
        return;
    }

    uint predecessor_count = 0u;
    for (uint predecessor_i = predecessor_start;
         predecessor_i < predecessor_end;
         ++predecessor_i)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
        if (edge_id >= edge_total)
        {
            report_structure_failure(row);
            return;
        }
        OptIrEdge edge = opt_ir_edges[edge_id];
        if (opt_ir_edge_to_block(edge.packed_target) != demand.block ||
            edge.from_block >= block_total)
        {
            report_structure_failure(row);
            return;
        }
        if (opt_ir_reachable[edge.from_block] != 0u)
            predecessor_count += 1u;
    }
    uint argument = opt_ir_ssa_block_argument_prefix[row];
    uint argument_end = row + 1u < total
        ? opt_ir_ssa_block_argument_prefix[row + 1u]
        : argument_total;
    uint incoming_start = opt_ir_ssa_demand_resolutions[row];
    if (argument > argument_end || argument_end > argument_total ||
        argument_end - argument > 1u || incoming_start > incoming_total)
    {
        report_structure_failure(row);
        return;
    }
    bool is_join = argument_end != argument;
    OptIrSsaValueRef resolution;
    resolution.kind = OPT_IR_SSA_SOURCE_INVALID;
    resolution.payload = INVALID;

    if (is_join)
    {
        uint incoming_count = predecessor_count;
        if (argument >= argument_total || incoming_start > incoming_total ||
            incoming_count > incoming_total - incoming_start)
        {
            report_structure_failure(row);
            opt_ir_ssa_demand_resolutions[row] =
                opt_ir_pack_ssa_source(resolution);
            return;
        }

        OptIrBlockArgument block_argument;
        block_argument.block_id = demand.block;
        block_argument.declaration = demand.declaration;
        block_argument.incoming_start = incoming_start;
        block_argument.incoming_count = incoming_count;
        opt_ir_ssa_block_arguments[argument] = block_argument;
        resolution.kind = OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT;
        resolution.payload = argument;

        uint reachable_ordinal = 0u;
        for (uint predecessor_i = predecessor_start;
             predecessor_i < predecessor_end;
             ++predecessor_i)
        {
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
            if (edge_id >= edge_total)
            {
                report_structure_failure(row);
                continue;
            }
            OptIrEdge edge = opt_ir_edges[edge_id];
            if (opt_ir_edge_to_block(edge.packed_target) != demand.block ||
                edge.from_block >= block_total)
            {
                report_structure_failure(row);
                continue;
            }
            if (opt_ir_reachable[edge.from_block] == 0u)
                continue;
            OptIrSsaValueRef source = predecessor_source(
                demand.declaration,
                edge.from_block,
                total,
                declaration_block_total,
                access_total);
            if (source.kind == OPT_IR_SSA_SOURCE_INVALID)
                report_structure_failure(row);
            OptIrBlockArgumentIncoming incoming;
            incoming.predecessor = edge.from_block;
            incoming.source = opt_ir_pack_ssa_source(source);
            opt_ir_ssa_block_argument_incoming[
                incoming_start + reachable_ordinal] = incoming;
            reachable_ordinal += 1u;
        }
        if (reachable_ordinal != predecessor_count)
            report_structure_failure(row);
    }
    else if (predecessor_count == 1u)
    {
        for (uint predecessor_i = predecessor_start;
             predecessor_i < predecessor_end;
             ++predecessor_i)
        {
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
            if (edge_id >= edge_total) continue;
            OptIrEdge edge = opt_ir_edges[edge_id];
            if (edge.from_block >= block_total ||
                opt_ir_reachable[edge.from_block] == 0u)
                continue;
            if (opt_ir_edge_to_block(edge.packed_target) == demand.block &&
                edge.from_block < block_total)
                resolution = predecessor_source(
                    demand.declaration,
                    edge.from_block,
                    total,
                    declaration_block_total,
                    access_total);
        }
        if (resolution.kind == OPT_IR_SSA_SOURCE_INVALID)
            report_structure_failure(row);
    }

    opt_ir_ssa_demand_resolutions[row] = opt_ir_pack_ssa_source(resolution);
}
