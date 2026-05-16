// x86_64 node instruction range apply pass.
//
// This pass applies the scanned offsets from execution-order slots back to
// sparse per-node range records:
// x86_node_inst_range_record[node] = (start, count, local-kind, payload).

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint4> x86_node_inst_order_record;
StructuredBuffer<uint> x86_node_inst_order_status;
StructuredBuffer<uint> x86_node_inst_scan_local_prefix;
StructuredBuffer<uint> x86_node_inst_scan_block_prefix;

RWStructuredBuffer<uint4> x86_node_inst_range_record;
RWStructuredBuffer<uint> x86_node_inst_range_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_INSTS = 256u;
static const uint X86_NODE_INST_ORDER_OK = 1u;
static const uint X86_NODE_INST_RANGE_OK = 1u;
static const uint X86_ERR_NODE_INST_ORDER = 12u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

bool count_status_ok()
{
    return x86_node_inst_order_status[0u] == X86_NODE_INST_ORDER_OK &&
           x86_node_inst_order_status[1u] == 0u;
}

uint scan_total()
{
    return gScan.n_blocks == 0u ? 0u : x86_node_inst_scan_block_prefix[gScan.n_blocks - 1u];
}

uint scanned_prefix_for_node(uint node)
{
    uint block_i = node / WG_SIZE;
    uint prior_blocks = block_i == 0u ? 0u : x86_node_inst_scan_block_prefix[block_i - 1u];
    return prior_blocks + x86_node_inst_scan_local_prefix[node];
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
    uint slot = linear_dispatch_id(tid);
    uint total = scan_total();
    bool ok = count_status_ok() && total <= MAX_X86_INSTS;

    if (slot == 0u)
        publish_status(ok, total);

    if (!ok || slot >= gScan.n_items)
        return;

    uint4 count = x86_node_inst_order_record[slot];
    uint node = count.x;
    if (node == INVALID || count.y == INVALID)
        return;

    uint start_inst = scanned_prefix_for_node(slot);
    if (start_inst + count.y <= MAX_X86_INSTS)
        x86_node_inst_range_record[node] = uint4(start_inst, count.y, count.z, count.w);
}
