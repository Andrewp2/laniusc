// Publish WASM body status from scanned body fragment lengths.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> body_scan_block_prefix;

RWStructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint BODY_STATUS_SLOT_COUNT = 7u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_total_len()
{
    return inclusive_scan_total(gScan.n_blocks, body_scan_block_prefix);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot = linear_dispatch_id(tid);
    uint input_error_code = status[2u];
    GroupMemoryBarrierWithGroupSync();

    if (slot >= BODY_STATUS_SLOT_COUNT || input_error_code != 0u)
        return;

    uint total_len = body_total_len();
    bool ok = total_len <= gScan.out_capacity;

    if (slot < 4u)
    {
        if (slot == 0u)
            body_status[0u] = ok ? total_len : 0u;
        else if (slot == 1u)
            body_status[1u] = ok ? 1u : 0u;
        else if (slot == 2u)
            body_status[2u] = ok ? 0u : ERR_UNSUPPORTED_SOURCE_SHAPE;
        else
            body_status[3u] = ok ? INVALID : total_len;
        return;
    }

    uint status_slot = slot - 3u;
    if (status_slot == 1u)
        status[1u] = 0u;
    else if (status_slot == 2u)
        status[2u] = ok ? 0u : ERR_UNSUPPORTED_SOURCE_SHAPE;
    else
        status[3u] = ok ? INVALID : total_len;
}
