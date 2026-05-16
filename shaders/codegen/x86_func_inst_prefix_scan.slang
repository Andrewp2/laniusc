// x86_64 function instruction range apply pass.
//
// Earlier passes produce ordered count rows, local scan prefixes, and inclusive
// block prefixes. This pass applies those scanned offsets back to sparse
// per-function range records consumed by x86_func_layout.

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint4> x86_func_inst_order_record;
StructuredBuffer<uint> x86_func_inst_order_slot;
StructuredBuffer<uint> x86_func_inst_order_status;
StructuredBuffer<uint> x86_func_inst_scan_local_prefix;
StructuredBuffer<uint> x86_func_inst_scan_block_prefix;

RWStructuredBuffer<uint4> x86_func_inst_range_record;
RWStructuredBuffer<uint> x86_func_inst_range_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_INSTS = 256u;
static const uint X86_FUNC_INST_ORDER_OK = 1u;
static const uint X86_FUNC_INST_RANGE_OK = 1u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

bool order_status_ok()
{
    return x86_func_inst_order_status[0u] == X86_FUNC_INST_ORDER_OK &&
           x86_func_inst_order_status[1u] == 0u;
}

uint scan_total()
{
    return gScan.n_blocks == 0u ? 0u : x86_func_inst_scan_block_prefix[gScan.n_blocks - 1u];
}

uint scanned_prefix_for_slot(uint slot)
{
    uint block_i = slot / WG_SIZE;
    uint prior_blocks = block_i == 0u ? 0u : x86_func_inst_scan_block_prefix[block_i - 1u];
    return prior_blocks + x86_func_inst_scan_local_prefix[slot];
}

void publish_status(bool ok, uint total)
{
    x86_func_inst_range_status[0u] = ok ? X86_FUNC_INST_RANGE_OK : 0u;
    x86_func_inst_range_status[1u] = ok ? 0u :
                                      (x86_func_inst_order_status[1u] == 0u ?
                                       X86_ERR_UNSUPPORTED_RETURN :
                                       x86_func_inst_order_status[1u]);
    x86_func_inst_range_status[2u] = ok ? INVALID :
                                      (x86_func_inst_order_status[1u] == 0u ?
                                       total :
                                       x86_func_inst_order_status[2u]);
    x86_func_inst_range_status[3u] = ok ? total : 0u;
    x86_func_inst_range_status[4u] = ok ? x86_func_inst_order_status[4u] : INVALID;
    x86_func_inst_range_status[5u] = ok ? x86_func_inst_order_status[5u] : INVALID;
    x86_func_inst_range_status[6u] = ok ? x86_func_inst_order_status[6u] : 0u;
    x86_func_inst_range_status[7u] = ok ? x86_func_inst_order_status[7u] : INVALID;
    x86_func_inst_range_status[8u] = ok ? x86_func_inst_order_status[8u] : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    uint total = scan_total();
    bool upstream_ok = order_status_ok();
    bool total_ok = upstream_ok &&
                    total == x86_func_inst_order_status[3u] &&
                    total != 0u &&
                    total <= MAX_X86_INSTS;

    if (node_i == 0u)
        publish_status(total_ok, total);

    if (!total_ok || node_i >= gScan.n_items - 1u)
        return;

    uint slot = x86_func_inst_order_slot[node_i];
    if (slot == INVALID || slot >= gScan.n_items)
        return;

    uint4 ordered = x86_func_inst_order_record[slot];
    if (ordered.x != node_i || ordered.y == 0u || ordered.y == INVALID)
        return;

    uint start_inst = scanned_prefix_for_slot(slot);
    if (start_inst + ordered.y <= MAX_X86_INSTS)
        x86_func_inst_range_record[node_i] = uint4(start_inst, ordered.y, ordered.z, ordered.w);
}
