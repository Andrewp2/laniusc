// x86_64 node instruction-count block-prefix scan.
//
// scan_step == 0 seeds inclusive block prefixes from local block sums. Later
// dispatches ping-pong prefix buffers with scan_step = 1, 2, 4, ...

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_node_inst_scan_block_sum;
StructuredBuffer<uint> x86_node_inst_scan_block_prefix_in;
RWStructuredBuffer<uint> x86_node_inst_scan_block_prefix_out;

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
        x86_node_inst_scan_block_prefix_out[i] = x86_node_inst_scan_block_sum[i];
        return;
    }

    uint value = x86_node_inst_scan_block_prefix_in[i];
    if (i >= gScan.scan_step)
        value += x86_node_inst_scan_block_prefix_in[i - gScan.scan_step];
    x86_node_inst_scan_block_prefix_out[i] = value;
}
