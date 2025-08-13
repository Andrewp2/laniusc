// Multi-round inclusive scan over per-block uint2 totals (ALL, KEPT).
// Ping/pong buffers are provided; after the final round the host copies
// the last writer (ping or pong) into block_prefix_pair.

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
[numthreads(1, 1, 1)]
void sum_scan_block_totals_inclusive(uint3 tid: SV_DispatchThreadID,
                                     uint3 gid: SV_GroupID)
{
    const uint i = gid.x; // one thread per block element

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
