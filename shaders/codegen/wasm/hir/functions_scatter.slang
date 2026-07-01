// Scatter scanned WASM function slots by declaration-token order.

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

StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_scan_local_prefix;
StructuredBuffer<uint> wasm_func_scan_block_prefix;

RWStructuredBuffer<uint> wasm_func_slot_by_token;
RWStructuredBuffer<uint> wasm_func_token_by_slot;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint slot_prefix(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        wasm_func_scan_local_prefix,
        wasm_func_scan_block_prefix);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token_i = linear_dispatch_id(tid);
    if (token_i >= gScan.n_items || wasm_func_flag[token_i] == 0u)
        return;

    uint slot = slot_prefix(token_i);
    if (slot >= gScan.n_items)
        return;

    wasm_func_slot_by_token[token_i] = slot;
    wasm_func_token_by_slot[slot] = token_i;
}
