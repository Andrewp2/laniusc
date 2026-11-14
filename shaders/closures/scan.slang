// Inclusive prefix sum over four-word rows, in tiles of TILE_ROWS rows.
// Mode 0 writes each tile's total. Mode 1, one workgroup, turns the totals
// into each tile's exclusive offset. Mode 2 scans each tile from its offset.
// A sum of one tile records mode 2 alone.

struct ScanParams
{
    uint count;
    uint mode;
    uint tiles;
    uint reserved0;
};

ConstantBuffer<ScanParams> gScan;
StructuredBuffer<uint4> scan_in;
RWStructuredBuffer<uint4> scan_tiles;
RWStructuredBuffer<uint4> scan_out;

static const uint WG_SIZE = 256u;
static const uint ROWS_PER_LANE = 8u;
static const uint TILE_ROWS = WG_SIZE * ROWS_PER_LANE;
static const uint MAX_GROUPS_X = 65535u;

static const uint MODE_TILE_TOTALS = 0u;
static const uint MODE_TILE_OFFSETS = 1u;
static const uint MODE_APPLY = 2u;

groupshared uint4 g_lanes[WG_SIZE];

// The sum of the values of the lanes before `lane`; `total` is the sum of
// every lane's value. Every lane of the workgroup calls it.
uint4 workgroup_exclusive(uint lane, uint4 value, out uint4 total)
{
    g_lanes[lane] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint offset = 1u; offset < WG_SIZE; offset <<= 1u)
    {
        uint4 add = lane >= offset ? g_lanes[lane - offset] : uint4(0u, 0u, 0u, 0u);
        GroupMemoryBarrierWithGroupSync();
        g_lanes[lane] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    total = g_lanes[WG_SIZE - 1u];
    uint4 inclusive = g_lanes[lane];
    GroupMemoryBarrierWithGroupSync();
    return inclusive - value;
}

// The sum of the rows of `lane` in tile `tile`.
uint4 lane_sum(uint tile, uint lane)
{
    uint first = tile * TILE_ROWS + lane * ROWS_PER_LANE;
    uint4 sum = uint4(0u, 0u, 0u, 0u);
    for (uint row = 0u; row < ROWS_PER_LANE; ++row)
    {
        if (first + row < gScan.count)
            sum += scan_in[first + row];
    }
    return sum;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group_id: SV_GroupID, uint3 local_id: SV_GroupThreadID)
{
    uint tile = group_id.x + group_id.y * MAX_GROUPS_X;
    uint lane = local_id.x;
    uint4 total;
    if (gScan.mode == MODE_TILE_OFFSETS)
    {
        if (tile != 0u)
            return;
        uint4 carry = uint4(0u, 0u, 0u, 0u);
        for (uint chunk = 0u; chunk < gScan.tiles; chunk += WG_SIZE)
        {
            uint index = chunk + lane;
            uint4 value = index < gScan.tiles ? scan_tiles[index] : uint4(0u, 0u, 0u, 0u);
            uint4 before = workgroup_exclusive(lane, value, total);
            if (index < gScan.tiles)
                scan_tiles[index] = carry + before;
            carry += total;
        }
        return;
    }
    if (tile >= gScan.tiles)
        return;
    uint4 before = workgroup_exclusive(lane, lane_sum(tile, lane), total);
    if (gScan.mode == MODE_TILE_TOTALS)
    {
        if (lane == 0u)
            scan_tiles[tile] = total;
        return;
    }
    uint4 running = before + (gScan.tiles > 1u ? scan_tiles[tile] : uint4(0u, 0u, 0u, 0u));
    uint first = tile * TILE_ROWS + lane * ROWS_PER_LANE;
    for (uint row = 0u; row < ROWS_PER_LANE; ++row)
    {
        if (first + row < gScan.count)
        {
            running += scan_in[first + row];
            scan_out[first + row] = running;
        }
    }
}
