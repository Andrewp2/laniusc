// Reusable u32 inclusive block-prefix scan for GPU name extraction.
//
// GPU-only scheduling contract:
// - scan_step == 0 initializes block prefix values from scan_block_sum.
// - Subsequent dispatches use scan_step = 1, 2, 4, ... and ping-pong
//   scan_block_prefix_in/out until all block sums have an inclusive prefix.
// - The final apply pass converts local exclusive prefixes to global exclusive
//   prefixes.

struct Params
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_block_sum;
StructuredBuffer<uint> scan_block_prefix_in;
RWStructuredBuffer<uint> scan_block_prefix_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gScan.n_blocks)
        return;

    if (gScan.scan_step == 0u)
    {
        scan_block_prefix_out[i] = scan_block_sum[i];
        return;
    }

    uint value = scan_block_prefix_in[i];
    if (i >= gScan.scan_step)
        value += scan_block_prefix_in[i - gScan.scan_step];
    scan_block_prefix_out[i] = value;
}
