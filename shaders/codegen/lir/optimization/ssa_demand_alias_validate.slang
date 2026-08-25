// Validates that every single-predecessor alias has collapsed to a source of
// the same declaration and that entry demands remain explicitly unresolved.

import codegen.lowering_ir;
import codegen.optimization_ir;
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
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_reachable;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
StructuredBuffer<uint> opt_ir_ssa_demand_resolutions;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
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
    uint access_total = min(
        opt_ir_access_total[0u], gParams.access_capacity);
    uint argument_total = min(
        opt_ir_ssa_block_argument_total[0u], gParams.demand_capacity);
    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    OptIrSsaValueRef resolution =
        opt_ir_unpack_ssa_source(opt_ir_ssa_demand_resolutions[row]);
    bool valid = demand.block < block_total &&
        resolution.kind != OPT_IR_SSA_SOURCE_DEMAND;
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

    if (valid && resolution.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
    {
        valid = resolution.payload < access_total &&
            opt_ir_accesses[resolution.payload].subject == demand.declaration;
        uint kind = valid
            ? opt_ir_access_kinds[resolution.payload]
            : OPT_IR_ACCESS_INVALID;
        valid = valid && (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION ||
            kind == OPT_IR_ACCESS_DECLARATION_WRITE);
    }
    else if (valid && resolution.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        valid = resolution.payload < argument_total;
        if (valid)
        {
            OptIrBlockArgument argument =
                opt_ir_ssa_block_arguments[resolution.payload];
            valid = argument.declaration == demand.declaration;
        }
    }
    else if (valid)
    {
        valid = resolution.kind == OPT_IR_SSA_SOURCE_INVALID &&
            resolution.payload == INVALID && predecessor_count == 0u;
    }

    if (!valid) report_structure_failure(row);
}
