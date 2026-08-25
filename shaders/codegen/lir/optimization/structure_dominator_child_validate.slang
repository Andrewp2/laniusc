// Validates compact dominator-tree ranges independently of scatter order.
// One invocation checks one parent cursor and, when present, one child row;
// no parent thread walks a potentially project-sized child range.

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
StructuredBuffer<uint> opt_ir_dominator_child_cursor;
StructuredBuffer<uint> opt_ir_dominator_children;
StructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= block_total) return;

    uint child_total = min(opt_ir_dominator_child_total[0u], block_total);
    uint start = opt_ir_dominator_child_prefix[block_id];
    uint end = block_id + 1u < block_total
        ? opt_ir_dominator_child_prefix[block_id + 1u] : child_total;
    bool valid = end >= start && end <= child_total &&
        opt_ir_dominator_child_cursor[block_id] == end;

    if (block_id < child_total)
    {
        uint row = block_id;
        uint lo = 0u;
        uint hi = block_total;
        while (lo < hi)
        {
            uint mid = lo + (hi - lo) / 2u;
            if (opt_ir_dominator_child_prefix[mid] <= row) lo = mid + 1u;
            else hi = mid;
        }
        uint parent = lo == 0u ? OPT_IR_DOMINATOR_INVALID : lo - 1u;
        uint child = opt_ir_dominator_children[row];
        valid = valid && parent < block_total && child < block_total &&
            opt_ir_immediate_dominator[child] == parent;
    }
    if (!valid) report_structure_failure(block_id);
}
