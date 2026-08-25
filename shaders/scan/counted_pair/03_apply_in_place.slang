// Adds scanned block carries to two in-place counted exclusive u32 scans.

struct Params
{
    uint n_items;
    uint n_blocks;
    uint min_items;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_block_prefix_left;
StructuredBuffer<uint> scan_block_prefix_right;
RWStructuredBuffer<uint> scan_values_left;
RWStructuredBuffer<uint> scan_values_right;
RWStructuredBuffer<uint> scan_total_left;
RWStructuredBuffer<uint> scan_total_right;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_items()
{
    return min(max(scan_count[0], gScan.min_items), gScan.n_items);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    uint count = active_items();
    uint blocks = (count + WG_SIZE - 1u) / WG_SIZE;
    if (i == 0u)
    {
        scan_total_left[0] = blocks == 0u ? 0u : scan_block_prefix_left[blocks - 1u];
        scan_total_right[0] = blocks == 0u ? 0u : scan_block_prefix_right[blocks - 1u];
    }
    if (i >= count)
        return;

    uint block_i = i / WG_SIZE;
    if (block_i != 0u)
    {
        scan_values_left[i] += scan_block_prefix_left[block_i - 1u];
        scan_values_right[i] += scan_block_prefix_right[block_i - 1u];
    }
}
