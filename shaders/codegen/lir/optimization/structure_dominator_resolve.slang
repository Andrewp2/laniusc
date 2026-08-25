// Resolves the only dominators left by the forward-predecessor seed: joins
// introduced by structured control. Every merge label is materialized by the
// same source HIR owner as its matching opener, and those synthetic rows are
// contiguous in stable OptIR identity even when scheduled child instructions
// execute between them. Scanning that owner-local recipe is bounded by the
// recipe itself, not by function or project size.

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
StructuredBuffer<OptIrNodeControl> opt_ir_control;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<uint> opt_ir_forward_predecessor_count_by_block;
RWStructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

bool opens_region(uint op)
{
    return op == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN;
}

uint matching_owner_local_opener(uint close_node, uint total)
{
    if (close_node >= total ||
        opt_ir_op(opt_ir_core[close_node]) != SEMANTIC_LIR_OP_CONTROL_END)
        return INVALID;

    uint owner = opt_ir_source_hir[close_node];
    uint nesting = 1u;
    uint candidate = close_node;
    while (candidate > 0u)
    {
        candidate -= 1u;
        if (opt_ir_source_hir[candidate] != owner) break;
        uint op = opt_ir_op(opt_ir_core[candidate]);
        if (op == SEMANTIC_LIR_OP_CONTROL_END)
            nesting += 1u;
        else if (opens_region(op))
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
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= block_total ||
        opt_ir_immediate_dominator[block_id] != OPT_IR_DOMINATOR_UNRESOLVED)
        return;

    uint total = min(opt_ir_total[0u], gParams.semantic_capacity);
    OptIrBlock block = opt_ir_blocks[block_id];
    if (block.position_start >= total ||
        opt_ir_forward_predecessor_count_by_block[block_id] < 2u)
    {
        report_structure_failure(block_id);
        return;
    }

    uint close_node = semantic_schedule_order[block.position_start];
    uint opener = matching_owner_local_opener(close_node, total);
    uint dominator = opener < total ? opt_ir_control[opener].block_id : INVALID;
    bool valid = dominator < block_total && dominator != block_id &&
        opt_ir_blocks[dominator].function_id == block.function_id &&
        opt_ir_blocks[dominator].position_start < block.position_start;
    if (!valid)
    {
        report_structure_failure(block_id);
        return;
    }
    opt_ir_immediate_dominator[block_id] = dominator;
}
