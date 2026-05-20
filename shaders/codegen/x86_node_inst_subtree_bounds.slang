// x86_64 subtree instruction row bounds.
//
// x86_node_inst_order materializes subtree slot bounds while the Pareas-style
// subtree-end histogram prefix is still live. After the instruction-count scan,
// this pass maps those slot bounds to virtual-instruction row bounds. Later
// node-local generation consumes this table instead of scanning subtrees.

import gpu_index;
import prefix_scan;
import status;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint4> x86_node_inst_subtree_slot_bounds;
StructuredBuffer<uint> x86_node_inst_range_status;
StructuredBuffer<uint> x86_node_inst_scan_local_prefix;
StructuredBuffer<uint> x86_node_inst_scan_block_prefix;

RWStructuredBuffer<uint2> x86_node_inst_subtree_bounds_record;
RWStructuredBuffer<uint> x86_node_inst_subtree_bounds_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_RANGE_OK = 1u;
static const uint X86_NODE_INST_SUBTREE_BOUNDS_OK = 1u;
static const uint X86_ERR_NODE_INST_SUBTREE_BOUNDS = 17u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool upstream_ok()
{
    return x86_node_inst_range_status[0u] == X86_NODE_INST_RANGE_OK &&
           x86_node_inst_range_status[1u] == 0u &&
           x86_node_inst_range_status[3u] <= gScan.inst_capacity;
}

uint scanned_prefix_for_slot(uint slot)
{
    return global_exclusive_prefix(
        slot,
        WG_SIZE,
        x86_node_inst_scan_local_prefix,
        x86_node_inst_scan_block_prefix);
}

bool row_for_slot(uint slot, uint total_rows, out uint row)
{
    row = INVALID;
    if (slot >= gScan.n_items)
    {
        if (slot == gScan.n_items)
        {
            row = total_rows;
            return true;
        }
        return false;
    }
    row = scanned_prefix_for_slot(slot);
    return row <= total_rows;
}

void publish_status(bool ok, uint total_rows)
{
    x86_node_inst_subtree_bounds_status[0u] =
        ok ? X86_NODE_INST_SUBTREE_BOUNDS_OK : 0u;
    x86_node_inst_subtree_bounds_status[1u] = ok ? 0u :
        stage_status4_error_or(
            x86_node_inst_range_status,
            X86_ERR_NODE_INST_SUBTREE_BOUNDS);
    x86_node_inst_subtree_bounds_status[2u] = ok ? INVALID :
        stage_status4_detail_or(x86_node_inst_range_status, total_rows);
    x86_node_inst_subtree_bounds_status[3u] = ok ? total_rows : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    uint total_rows = ok ? x86_node_inst_range_status[3u] : 0u;

    if (node == 0u)
        publish_status(ok, total_rows);

    if (!ok || node >= gScan.n_items)
        return;

    uint4 slots = x86_node_inst_subtree_slot_bounds[node];
    if (slots.x == INVALID || slots.y == INVALID || slots.x >= slots.y)
    {
        x86_node_inst_subtree_bounds_record[node] = uint2(INVALID, INVALID);
        return;
    }

    uint first_row = INVALID;
    uint after_row = INVALID;
    if (!row_for_slot(slots.x, total_rows, first_row) ||
        !row_for_slot(slots.y, total_rows, after_row) ||
        first_row == INVALID ||
        after_row == INVALID ||
        first_row >= after_row)
    {
        x86_node_inst_subtree_bounds_record[node] = uint2(INVALID, INVALID);
        publish_stage_error_min_detail4(
            x86_node_inst_subtree_bounds_status,
            X86_ERR_NODE_INST_SUBTREE_BOUNDS,
            node);
        return;
    }

    x86_node_inst_subtree_bounds_record[node] = uint2(first_row, after_row);
}
