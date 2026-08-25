// Assigns the innermost active structured region to every scheduled OptIR
// node with one logarithmic segment-tree point query per invocation.

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
StructuredBuffer<uint> opt_ir_region_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrRegion> opt_ir_regions;
StructuredBuffer<uint> opt_ir_region_ownership_tree;
RWStructuredBuffer<OptIrNodeControl> opt_ir_control;
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

uint region_for_position(uint position)
{
    uint cursor = gParams.semantic_capacity + position;
    uint encoded = 0u;
    while (cursor != 0u)
    {
        encoded = max(encoded, opt_ir_region_ownership_tree[cursor]);
        cursor >>= 1u;
    }
    return encoded == 0u ? INVALID : encoded - 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_total[0u], gParams.semantic_capacity);
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    if (node >= total)
    {
        report_structure_failure(node);
        return;
    }
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint region_total = min(opt_ir_region_total[0u], gParams.block_capacity);
    uint block_id = opt_ir_control[node].block_id;
    uint region_id = region_for_position(position);
    bool valid = block_id < block_total;
    if (region_id != INVALID)
    {
        valid = valid && region_id < region_total;
        if (valid)
        {
            OptIrRegion region = opt_ir_regions[region_id];
            valid = region.function_id == opt_ir_blocks[block_id].function_id &&
                region.position_start <= position && position < region.position_end;
            if (opens_region(opt_ir_op(opt_ir_core[node])))
            {
                uint expected_parent = position == 0u
                    ? INVALID : region_for_position(position - 1u);
                if (expected_parent != INVALID)
                {
                    valid = valid && expected_parent < region_total;
                    if (valid && opt_ir_regions[expected_parent].function_id !=
                        region.function_id)
                        expected_parent = INVALID;
                }
                valid = valid && region.position_start == position &&
                    region.parent_region == expected_parent;
            }
        }
    }
    if (!valid)
    {
        report_structure_failure(node);
        return;
    }

    OptIrNodeControl control = opt_ir_control[node];
    control.region_id = region_id;
    opt_ir_control[node] = control;
}
