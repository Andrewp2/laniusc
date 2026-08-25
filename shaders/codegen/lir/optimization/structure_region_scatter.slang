// Materializes one region interval per structured opener. Matching is local to
// the opener's synthetic semantic recipe: those rows have contiguous stable
// OptIR IDs even when scheduled child instructions occur inside the interval.

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
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> opt_ir_position_by_node;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_region_start_flag;
StructuredBuffer<uint> opt_ir_region_prefix;
StructuredBuffer<uint> opt_ir_region_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
RWStructuredBuffer<OptIrNodeControl> opt_ir_control;
RWStructuredBuffer<OptIrRegion> opt_ir_regions;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint node)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

bool opens_region(uint op)
{
    return op == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN;
}

uint matching_owner_local_close(uint opener, uint total)
{
    uint owner = opt_ir_source_hir[opener];
    uint nesting = 1u;
    for (uint candidate = opener + 1u; candidate < total; ++candidate)
    {
        if (opt_ir_source_hir[candidate] != owner) break;
        uint op = opt_ir_op(opt_ir_core[candidate]);
        if (opens_region(op))
            nesting += 1u;
        else if (op == SEMANTIC_LIR_OP_CONTROL_END)
        {
            nesting -= 1u;
            if (nesting == 0u) return candidate;
        }
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_total[0u], gParams.semantic_capacity);
    if (position >= total || opt_ir_region_start_flag[position] == 0u) return;

    uint node = semantic_schedule_order[position];
    uint region_id = opt_ir_region_prefix[position];
    uint region_total = min(opt_ir_region_total[0u], gParams.block_capacity);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint close = node < total ? matching_owner_local_close(node, total) : INVALID;
    uint close_position = close < total ? opt_ir_position_by_node[close] : INVALID;
    uint block_id = node < total ? opt_ir_control[node].block_id : INVALID;
    bool valid = region_id < region_total && block_id < block_total &&
        close_position > position && close_position < total;
    if (!valid)
    {
        report_structure_failure(node);
        return;
    }

    OptIrRegion region;
    region.function_id = opt_ir_blocks[block_id].function_id;
    region.parent_region = INVALID;
    region.position_start = position;
    region.position_end = close_position;
    opt_ir_regions[region_id] = region;

    OptIrNodeControl control = opt_ir_control[node];
    control.region_id = region_id;
    opt_ir_control[node] = control;
}
