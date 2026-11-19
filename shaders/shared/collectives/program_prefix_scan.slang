import shared.collectives.prefix_scan;
import shared.collectives.step_program;

groupshared uint step_program_scan_last;

uint step_program_scan_tile_sum(uint lane, uint inclusive)
{
    if (lane == STEP_PROGRAM_GROUP_LANES - 1u)
        step_program_scan_last = inclusive;
    GroupMemoryBarrierWithGroupSync();
    uint sum = step_program_scan_last;
    GroupMemoryBarrierWithGroupSync();
    return sum;
}

// Scans unsigned words into exclusive offsets. Each group owns a contiguous
// range of tiles. It publishes its sum before any group reads the carries.
// The caller ends the apply step before reading the scan results elsewhere
// or reusing group_sums. Only program.groups scratch words are needed.
public bool step_program_prefix_scan(
    inout StepProgram program,
    uint rows,
    RWStructuredBuffer<uint> input,
    RWStructuredBuffer<uint> prefix,
    RWStructuredBuffer<uint> total,
    RWStructuredBuffer<uint> group_sums)
{
    const uint tile_rows = STEP_PROGRAM_GROUP_LANES * 4u;
    uint lane = program.lane % STEP_PROGRAM_GROUP_LANES;
    uint group = program.lane / STEP_PROGRAM_GROUP_LANES;
    uint tiles = rows / tile_rows + uint(rows % tile_rows != 0u);
    uint tiles_per_group = tiles / program.groups + uint(tiles % program.groups != 0u);
    uint first_tile = min(tiles, group * tiles_per_group);
    uint end_tile = min(tiles, first_tile + tiles_per_group);
    uint carry = 0u;
    for (uint tile = first_tile; tile < end_tile; ++tile)
    {
        uint row = tile * tile_rows + lane * 4u;
        uint a = row < rows ? input[row] : 0u;
        uint b = row + 1u < rows ? input[row + 1u] : 0u;
        uint c = row + 2u < rows ? input[row + 2u] : 0u;
        uint d = row + 3u < rows ? input[row + 3u] : 0u;
        uint sum = a + b + c + d;
        uint inclusive = prefix_scan_u32_256(lane, sum);
        uint offset = carry + inclusive - sum;
        if (row < rows) prefix[row] = offset;
        if (row + 1u < rows) prefix[row + 1u] = offset + a;
        if (row + 2u < rows) prefix[row + 2u] = offset + a + b;
        if (row + 3u < rows) prefix[row + 3u] = offset + a + b + c;
        // Keep each lane's copy of the tile carry in registers.
        carry += step_program_scan_tile_sum(lane, inclusive);
    }

    if (program.groups == 1u)
    {
        if (lane == 0u) total[0u] = carry;
        return true;
    }
    if (lane == 0u) group_sums[group] = carry;
    if (!step_barrier(program)) return false;

    uint earlier_sum = lane < group ? group_sums[lane] : 0u;
    uint earlier_inclusive = prefix_scan_u32_256(lane, earlier_sum);
    uint group_carry = step_program_scan_tile_sum(lane, earlier_inclusive);
    if (lane == 0u && group + 1u == program.groups)
        total[0u] = group_carry + carry;
    if (group == 0u) return true;
    for (uint tile = first_tile; tile < end_tile; ++tile)
    {
        uint row = tile * tile_rows + lane;
        for (uint i = 0u; i < 4u; ++i)
        {
            uint item = row + i * STEP_PROGRAM_GROUP_LANES;
            if (item < rows) prefix[item] += group_carry;
        }
    }
    return true;
}
