// Creates one downward and one upward Euler-tour arc for each reachable
// non-root dominator-tree node. `previous` links each per-function tour into a
// list; down arcs contribute one to the eventual preorder count.

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
StructuredBuffer<uint> opt_ir_dominator_child_total;
StructuredBuffer<uint> opt_ir_dominator_child_prefix;
StructuredBuffer<uint> opt_ir_dominator_child_row_by_block;
StructuredBuffer<uint> opt_ir_dominator_children;
StructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<OptIrDominatorTourLink> opt_ir_dominator_tour_link_out;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

uint child_range_end(uint block, uint block_total, uint child_total)
{
    return block + 1u < block_total
        ? opt_ir_dominator_child_prefix[block + 1u]
        : child_total;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arc = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (arc >= block_total * 2u) return;
    uint child_total = min(opt_ir_dominator_child_total[0u], block_total);
    uint block = arc >> 1u;
    bool upward = (arc & 1u) != 0u;

    OptIrDominatorTourLink link;
    link.previous = INVALID;
    link.down_count = 0u;
    uint parent = opt_ir_immediate_dominator[block];
    if (parent == block || parent == OPT_IR_DOMINATOR_UNREACHABLE)
    {
        opt_ir_dominator_tour_link_out[arc] = link;
        return;
    }

    bool valid = parent < block_total;
    if (!upward)
    {
        uint child_row = valid
            ? opt_ir_dominator_child_row_by_block[block] : INVALID;
        uint sibling_start = valid
            ? opt_ir_dominator_child_prefix[parent] : INVALID;
        valid = valid && child_row >= sibling_start &&
            child_row < child_range_end(parent, block_total, child_total) &&
            opt_ir_dominator_children[child_row] == block;
        if (valid && child_row != sibling_start)
        {
            uint previous_sibling =
                opt_ir_dominator_children[child_row - 1u];
            valid = previous_sibling < block_total;
            link.previous = valid ? previous_sibling * 2u + 1u : INVALID;
        }
        else if (valid && opt_ir_immediate_dominator[parent] != parent)
            link.previous = parent * 2u;
        link.down_count = 1u;
    }
    else
    {
        uint start = opt_ir_dominator_child_prefix[block];
        uint end = child_range_end(block, block_total, child_total);
        valid = valid && end >= start && end <= child_total;
        if (valid && end != start)
        {
            uint last_child = opt_ir_dominator_children[end - 1u];
            valid = last_child < block_total;
            link.previous = valid ? last_child * 2u + 1u : INVALID;
        }
        else if (valid)
            link.previous = block * 2u;
    }

    if (!valid)
    {
        report_structure_failure(block);
        link.previous = INVALID;
        link.down_count = 0u;
    }
    opt_ir_dominator_tour_link_out[arc] = link;
}
