// Independently validates pruned block arguments, their predecessor coverage,
// and every symbolic demand resolution.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_block_argument_lookup;
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
StructuredBuffer<uint> opt_ir_ssa_demand_resolutions;
StructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
StructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool valid_source(
    OptIrSsaValueRef source,
    uint demand_total,
    uint argument_total,
    uint access_total)
{
    return (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
            source.payload < access_total) ||
        (source.kind == OPT_IR_SSA_SOURCE_DEMAND &&
            source.payload < demand_total) ||
        (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            source.payload < argument_total);
}

bool source_matches_predecessor(
    OptIrSsaValueRef source,
    uint declaration,
    uint predecessor,
    uint demand_total,
    uint declaration_block_total,
    uint access_total)
{
    uint definition = opt_ir_outgoing_local_definition(
        declaration,
        predecessor,
        declaration_block_total,
        access_total);
    if (definition != INVALID)
        return source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
            source.payload == definition;
    uint demand = opt_ir_find_ssa_demand(
        declaration, predecessor, demand_total);
    return demand != INVALID &&
        source.kind == OPT_IR_SSA_SOURCE_DEMAND &&
        source.payload == demand;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = opt_ir_active_ssa_demand_total(gParams.demand_capacity);
    if (row >= total) return;

    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint access_total = opt_ir_active_access_total(gParams.access_capacity);
    uint declaration_block_total = opt_ir_active_declaration_block_total(
        gParams.declaration_block_capacity);
    uint argument_total = min(
        opt_ir_ssa_block_argument_total[0u], gParams.demand_capacity);
    uint incoming_total = min(
        opt_ir_ssa_block_argument_incoming_total[0u],
        gParams.incoming_capacity);
    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    bool valid = demand.block < block_total;
    uint predecessor_start = valid
        ? opt_ir_predecessor_prefix[demand.block] : 0u;
    uint predecessor_end = valid
        ? (demand.block + 1u < block_total
            ? opt_ir_predecessor_prefix[demand.block + 1u]
            : edge_total)
        : 0u;
    valid = valid && predecessor_start <= predecessor_end &&
        predecessor_end <= edge_total;
    uint predecessor_count = 0u;
    for (uint predecessor_i = predecessor_start;
         valid && predecessor_i < predecessor_end;
         ++predecessor_i)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
        valid = edge_id < edge_total;
        if (!valid) break;
        OptIrEdge edge = opt_ir_edges[edge_id];
        valid = edge.from_block < block_total &&
            opt_ir_edge_to_block(edge.packed_target) == demand.block;
        if (valid &&
            opt_ir_reachable[edge.from_block] != 0u)
            predecessor_count += 1u;
    }
    uint argument = opt_ir_ssa_block_argument_prefix[row];
    uint argument_end = row + 1u < total
        ? opt_ir_ssa_block_argument_prefix[row + 1u]
        : argument_total;
    valid = valid && argument <= argument_end &&
        argument_end <= argument_total && argument_end - argument <= 1u;
    bool is_join = valid && argument_end != argument;
    valid = valid && is_join == (predecessor_count > 1u);

    OptIrSsaValueRef resolution =
        opt_ir_unpack_ssa_source(opt_ir_ssa_demand_resolutions[row]);
    if (is_join)
    {
        valid = valid && argument < argument_total &&
            resolution.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            resolution.payload == argument;
        uint incoming_start = 0u;
        uint incoming_end = 0u;
        if (valid)
        {
            OptIrBlockArgument block_argument =
                opt_ir_ssa_block_arguments[argument];
            incoming_start = block_argument.incoming_start;
            incoming_end = opt_ir_ssa_block_argument_incoming_end(
                argument, argument_total, incoming_total);
            valid = block_argument.block_id == demand.block &&
                block_argument.declaration == demand.declaration &&
                incoming_start <= incoming_end &&
                incoming_end <= incoming_total &&
                block_argument.incoming_count == predecessor_count &&
                incoming_end - incoming_start == predecessor_count;
        }
        uint reachable_ordinal = 0u;
        for (uint predecessor_i = predecessor_start;
             valid && predecessor_i < predecessor_end;
             ++predecessor_i)
        {
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
            valid = edge_id < edge_total;
            if (!valid) break;
            OptIrEdge edge = opt_ir_edges[edge_id];
            if (edge.from_block < block_total &&
                opt_ir_reachable[edge.from_block] == 0u)
                continue;
            OptIrBlockArgumentIncoming incoming =
                opt_ir_ssa_block_argument_incoming[
                    incoming_start + reachable_ordinal];
            OptIrSsaValueRef source =
                opt_ir_unpack_ssa_source(incoming.source);
            valid = incoming.predecessor == edge.from_block &&
                opt_ir_edge_to_block(edge.packed_target) ==
                demand.block &&
                valid_source(source, total, argument_total, access_total) &&
                source_matches_predecessor(
                    source,
                    demand.declaration,
                    edge.from_block,
                    total,
                    declaration_block_total,
                    access_total);
            reachable_ordinal += 1u;
        }
        valid = valid && reachable_ordinal == predecessor_count;
    }
    else if (predecessor_count == 1u)
    {
        valid = valid && valid_source(
            resolution, total, argument_total, access_total) &&
            resolution.kind != OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT;
        if (valid)
        {
            bool found = false;
            for (uint predecessor_i = predecessor_start;
                 valid && predecessor_i < predecessor_end;
                 ++predecessor_i)
            {
                uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
                valid = edge_id < edge_total;
                if (!valid) break;
                OptIrEdge edge = opt_ir_edges[edge_id];
                if (edge.from_block < block_total &&
                    opt_ir_reachable[edge.from_block] == 0u)
                    continue;
                found = true;
                valid = source_matches_predecessor(
                    resolution, demand.declaration, edge.from_block,
                    total, declaration_block_total, access_total);
            }
            valid = valid && found;
        }
    }
    else
    {
        // A demanded function-entry value has no reaching definition. Keep it
        // explicit for the SSA rewrite to diagnose against source provenance.
        valid = valid && resolution.kind == OPT_IR_SSA_SOURCE_INVALID &&
            resolution.payload == INVALID;
    }

    if (!valid) report_structure_failure(row);
}
