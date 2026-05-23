// x86_64 node instruction range apply pass.
//
// This pass applies the scanned offsets from execution-order slots back to
// sparse per-node range records:
// x86_node_inst_range_start/info[node] = (start, packed count/kind). The canonical
// per-node instruction-count record retains payload metadata.
//
// x86_node_inst_order_status[3] is the compact order slot count. The total
// virtual instruction row count is computed here from the scanned per-slot
// instruction counts.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_node_inst_order_record;
StructuredBuffer<uint> x86_node_inst_count_info;
StructuredBuffer<uint> x86_node_inst_count_payload;
StructuredBuffer<uint> x86_node_inst_order_status;
StructuredBuffer<uint> x86_node_inst_scan_local_prefix;
StructuredBuffer<uint> x86_node_inst_scan_block_prefix;

RWStructuredBuffer<uint> x86_node_inst_range_start;
RWStructuredBuffer<uint> x86_node_inst_range_info;
RWStructuredBuffer<uint> x86_node_inst_range_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_ORDER_OK = 1u;
static const uint X86_NODE_INST_RANGE_OK = 1u;
static const uint X86_ERR_NODE_INST_ORDER = 12u;
static const uint X86_NODE_INST_COUNT_STRIDE = 2u;
static const uint X86_NODE_INST_COUNT_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_COUNT_COUNT_MASK = 0x0fffffffu;
static const uint X86_NODE_INST_RANGE_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint X86_NODE_INST_ORDER_STRIDE = 3u;
static const uint X86_NODE_INST_ORDER_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_ORDER_COUNT_MASK = 0x0fffffffu;

uint order_record_word(uint slot, uint field)
{
    return row_major_load<uint>(
        x86_node_inst_order_record,
        slot,
        X86_NODE_INST_ORDER_STRIDE,
        field,
        INVALID);
}

uint4 order_record(uint slot)
{
    uint node = order_record_word(slot, 0u);
    uint info = order_record_word(slot, 1u);
    uint payload = order_record_word(slot, 2u);
    uint count = info == INVALID ? INVALID : info & X86_NODE_INST_ORDER_COUNT_MASK;
    uint kind = info == INVALID ? INVALID : info >> X86_NODE_INST_ORDER_KIND_SHIFT;
    return uint4(node, count, kind, payload);
}

uint node_inst_count_word(uint node, uint field)
{
    if (field == 0u)
        return x86_node_inst_count_info[node];
    if (field == 1u)
        return x86_node_inst_count_payload[node];
    return INVALID;
}

uint4 node_inst_count_record(uint node)
{
    uint info = node_inst_count_word(node, 0u);
    uint payload = node_inst_count_word(node, 1u);
    uint count = info == INVALID ? INVALID : info & X86_NODE_INST_COUNT_COUNT_MASK;
    uint kind = info == INVALID ? INVALID : info >> X86_NODE_INST_COUNT_KIND_SHIFT;
    return uint4(node, count, kind, payload);
}

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool order_status_ok()
{
    return x86_node_inst_order_status[0u] == X86_NODE_INST_ORDER_OK &&
           x86_node_inst_order_status[1u] == 0u;
}

uint saturating_sum_or_oob(uint left, uint right)
{
    uint sum = left + right;
    return sum < left ? gScan.inst_capacity + 1u : sum;
}

uint scan_total()
{
    uint order_count = min(x86_node_inst_order_status[3u], gScan.n_items);
    if (order_count == 0u)
        return 0u;

    uint last_slot = order_count - 1u;
    uint4 last = order_record(last_slot);
    if (last.y == INVALID)
        return gScan.inst_capacity + 1u;
    return saturating_sum_or_oob(scanned_prefix_for_slot(last_slot), last.y);
}

uint scanned_prefix_for_slot(uint slot)
{
    return global_exclusive_prefix(
        slot,
        WG_SIZE,
        x86_node_inst_scan_local_prefix,
        x86_node_inst_scan_block_prefix);
}

uint pack_range_info(uint count, uint local_kind)
{
    if (count > X86_NODE_INST_RANGE_COUNT_MASK)
        return INVALID;
    return (local_kind << X86_NODE_INST_RANGE_KIND_SHIFT) |
           (count & X86_NODE_INST_RANGE_COUNT_MASK);
}

void publish_status(bool ok, uint total)
{
    x86_node_inst_range_status[0u] = ok ? X86_NODE_INST_RANGE_OK : 0u;
    x86_node_inst_range_status[1u] = ok ? 0u :
                                     (x86_node_inst_order_status[1u] == 0u ?
                                      X86_ERR_NODE_INST_ORDER :
                                      x86_node_inst_order_status[1u]);
    x86_node_inst_range_status[2u] = ok ? INVALID :
                                     (x86_node_inst_order_status[1u] == 0u ?
                                      total :
                                      x86_node_inst_order_status[2u]);
    x86_node_inst_range_status[3u] = ok ? total : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint total = scan_total();
    bool ok = order_status_ok() && total <= gScan.inst_capacity;

    if (node == 0u)
        publish_status(ok, total);

    if (!ok || node >= gScan.n_items)
        return;

    uint4 count = node_inst_count_record(node);
    if (count.x != node || count.y == INVALID)
        return;

    if (count.y == 0u)
    {
        uint packed_zero_info = pack_range_info(0u, count.z);
        if (packed_zero_info != INVALID)
        {
            x86_node_inst_range_start[node] = INVALID;
            x86_node_inst_range_info[node] = packed_zero_info;
        }
        return;
    }

    uint slot = x86_node_inst_range_start[node];
    if (slot == INVALID || slot >= x86_node_inst_order_status[3u])
        return;

    uint start_inst = scanned_prefix_for_slot(slot);
    uint packed_info = pack_range_info(count.y, count.z);
    if (packed_info != INVALID && start_inst + count.y <= gScan.inst_capacity)
    {
        x86_node_inst_range_start[node] = start_inst;
        x86_node_inst_range_info[node] = packed_info;
    }
}
