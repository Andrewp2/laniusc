// Reusable u32 global exclusive prefix apply pass for GPU name extraction.
//
// GPU-only scheduling contract:
// - Dispatch after type_check_names_scan_01_blocks.slang has produced inclusive
//   block prefixes.
// - scan_output_prefix[i] receives the exclusive prefix for scan_input[i].
// - scan_total[0] receives the total sum, used as the compact record count.

struct Params
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_local_prefix;
StructuredBuffer<uint> scan_block_prefix;
RWStructuredBuffer<uint> scan_output_prefix;
RWStructuredBuffer<uint> scan_total;

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
    if (i == 0u)
        scan_total[0] = gScan.n_items == 0u || gScan.n_blocks == 0u
                            ? 0u
                            : scan_block_prefix[gScan.n_blocks - 1u];

    if (i >= gScan.n_items)
        return;

    uint block_i = i / WG_SIZE;
    uint prior_blocks = block_i == 0u ? 0u : scan_block_prefix[block_i - 1u];
    scan_output_prefix[i] = prior_blocks + scan_local_prefix[i];
}
