// Multi-round inclusive scan over per-block uint2 totals (ALL, KEPT).
// Ping/pong buffers are provided; after the final round the host copies
// the last writer (ping or pong) into block_prefix_pair.

import gpu_index;

static const uint PAIR_BLOCK_WIDTH = 256u; // must match pair_01
static const uint DISPATCH_X_STRIDE = 16776960u;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

struct Scan
{
    uint stride;
    uint use_ping_as_src;
};
ConstantBuffer<Scan> gScan;

RWStructuredBuffer<uint2> block_pair_ping; // length nb
RWStructuredBuffer<uint2> block_pair_pong; // length nb

[shader("compute")]
[numthreads(256, 1, 1)]
void pair_02_scan_block_totals(uint3 tid: SV_DispatchThreadID)
{
    const uint nb = (gParams.n + (PAIR_BLOCK_WIDTH - 1u)) / PAIR_BLOCK_WIDTH;
    const uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);

    if (i >= nb)
        return;

    // TODO: the shader should not be responsible for picking ping/pong
    // instead that should happen in the binding
    // because now we've added extra work to the shader
    if (gScan.use_ping_as_src != 0u)
    {
        uint2 val = block_pair_ping[i];
        if (i >= gScan.stride)
        {
            val += block_pair_ping[i - gScan.stride];
        }
        block_pair_pong[i] = val;
    }
    else
    {
        uint2 val = block_pair_pong[i];
        if (i >= gScan.stride)
        {
            val += block_pair_pong[i - gScan.stride];
        }
        block_pair_ping[i] = val;
    }
}
