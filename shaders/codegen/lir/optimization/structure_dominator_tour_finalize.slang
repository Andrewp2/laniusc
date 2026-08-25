// Converts ranked Euler arcs to an exact preorder and half-open subtree range
// for every reachable dominator-tree block.

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
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> opt_ir_dominator_child_total;
StructuredBuffer<uint> opt_ir_dominator_child_prefix;
StructuredBuffer<uint> opt_ir_dominator_children;
StructuredBuffer<uint> opt_ir_immediate_dominator;
StructuredBuffer<OptIrDominatorTourLink> opt_ir_dominator_tour_link;
RWStructuredBuffer<uint> opt_ir_dominator_preorder;
RWStructuredBuffer<uint> opt_ir_dominator_subtree_end;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block >= block_total) return;

    uint function_total = min(semantic_function_total[0u],
        gParams.hir_capacity);
    uint function_id = opt_ir_blocks[block].function_id;
    uint parent = opt_ir_immediate_dominator[block];
    bool valid = function_id < function_total;
    OptIrFunction function = valid ? opt_ir_functions[function_id]
        : opt_ir_functions[0u];
    uint preorder = INVALID;
    uint subtree_end = INVALID;

    if (parent == OPT_IR_DOMINATOR_UNREACHABLE)
    {
        opt_ir_dominator_preorder[block] = INVALID;
        opt_ir_dominator_subtree_end[block] = INVALID;
        return;
    }
    if (parent == block)
    {
        uint child_total = min(opt_ir_dominator_child_total[0u], block_total);
        uint start = opt_ir_dominator_child_prefix[block];
        uint end = block + 1u < block_total
            ? opt_ir_dominator_child_prefix[block + 1u] : child_total;
        valid = valid && function.entry_block == block && end >= start &&
            end <= child_total;
        uint descendants = 0u;
        if (valid && end != start)
        {
            uint last_child = opt_ir_dominator_children[end - 1u];
            valid = last_child < block_total;
            OptIrDominatorTourLink last = valid
                ? opt_ir_dominator_tour_link[last_child * 2u + 1u]
                : opt_ir_dominator_tour_link[0u];
            valid = valid && last.previous == INVALID;
            descendants = valid ? last.down_count : 0u;
        }
        preorder = function.block_start;
        subtree_end = preorder + descendants + 1u;
    }
    else
    {
        valid = valid && parent < block_total;
        OptIrDominatorTourLink down = valid
            ? opt_ir_dominator_tour_link[block * 2u]
            : opt_ir_dominator_tour_link[0u];
        OptIrDominatorTourLink up = valid
            ? opt_ir_dominator_tour_link[block * 2u + 1u]
            : opt_ir_dominator_tour_link[0u];
        valid = valid && down.previous == INVALID && up.previous == INVALID &&
            down.down_count != 0u && up.down_count >= down.down_count;
        preorder = function.block_start + down.down_count;
        subtree_end = preorder + up.down_count - down.down_count + 1u;
    }

    valid = valid && preorder >= function.block_start &&
        subtree_end > preorder &&
        subtree_end <= function.block_start + function.block_count;
    if (!valid)
    {
        report_structure_failure(block);
        preorder = INVALID;
        subtree_end = INVALID;
    }
    opt_ir_dominator_preorder[block] = preorder;
    opt_ir_dominator_subtree_end[block] = subtree_end;
}
