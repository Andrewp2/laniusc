// Publish scanned per-function body starts into durable function records.

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

StructuredBuffer<uint> object_body_len_by_slot;
StructuredBuffer<uint> object_body_scan_local_prefix;
StructuredBuffer<uint> object_body_scan_block_prefix;
RWStructuredBuffer<uint> object_function_record;

static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot = linear_dispatch_id(tid);
    if (slot >= gScan.n_items || object_body_len_by_slot[slot] == 0u)
        return;
    object_function_record[slot * 6u + 2u] = global_exclusive_prefix(
        slot,
        WG_SIZE,
        object_body_scan_local_prefix,
        object_body_scan_block_prefix);
}
