import shared.collectives.prefix_scan;
import shared.collectives.step_program;

public interface IStepProgramRadixKey
{
    static uint digit(uint row, uint step);
}

groupshared uint step_radix_histogram[256];
groupshared uint step_radix_bucket_base[256];
groupshared uint step_radix_lanes_by_key[8][256];

// Orders row IDs by consecutive low-to-high byte digits. A tile holds 256
// consecutive positions. Prefixing tile histograms in position order and
// ranking equal keys in lane order preserves stability across tiles too.
// histogram needs (ceil(rows / 256) + program.groups) * 256 words.
// bucket_total needs 256 words.
// digits must be positive and TKey.digit must return a byte.
// The caller ends the last scatter step before reading the resulting order.
public bool step_program_radix_sort<TKey : IStepProgramRadixKey>(
    inout StepProgram program,
    uint rows,
    uint digits,
    RWStructuredBuffer<uint> order,
    RWStructuredBuffer<uint> temporary,
    RWStructuredBuffer<uint> histogram,
    RWStructuredBuffer<uint> bucket_total)
{
    const uint size = STEP_PROGRAM_GROUP_LANES;
    uint lane = program.lane % size;
    uint group = program.lane / size;
    uint tiles = rows / size + uint(rows % size != 0u);
    if (tiles == 0u) return true;

    uint tiles_per_group = tiles / program.groups + uint(tiles % program.groups != 0u);
    uint first_tile = min(tiles, group * tiles_per_group);
    uint end_tile = min(tiles, first_tile + tiles_per_group);

    // Start on the side that leaves the last digit in order.
    for (uint digit = 0u; digit < digits; ++digit)
    {
        bool source_is_order = ((digits - digit) & 1u) == 0u;
        uint count = 0u;
        for (uint tile = first_tile; tile < end_tile; ++tile)
        {
            step_radix_histogram[lane] = 0u;
            GroupMemoryBarrierWithGroupSync();
            uint position = tile * size + lane;
            if (position < rows)
            {
                uint row = digit == 0u ? position :
                    source_is_order ? order[position] : temporary[position];
                InterlockedAdd(step_radix_histogram[TKey.digit(row, digit)], 1u);
            }
            GroupMemoryBarrierWithGroupSync();
            // This lane owns the same bucket in every tile of the group.
            histogram[tile * size + lane] = count;
            count += step_radix_histogram[lane];
            GroupMemoryBarrierWithGroupSync();
        }

        uint group_slot = (tiles + group) * size;
        histogram[group_slot + lane] = count;
        if (!step_barrier(program)) return false;

        if (program.groups > 1u)
        {
            // Only the group totals need a global prefix. The per-tile
            // offsets are already relative to each group's first tile.
            if (group == 0u)
            {
                uint sum = 0u;
                for (uint group_i = 0u; group_i < program.groups; ++group_i)
                {
                    uint slot = (tiles + group_i) * size + lane;
                    uint group_count = histogram[slot];
                    histogram[slot] = sum;
                    sum += group_count;
                }
                bucket_total[lane] = sum;
            }
            if (!step_barrier(program)) return false;
            if (first_tile < end_tile) count = bucket_total[lane];
        }

        if (first_tile < end_tile)
        {
            step_radix_bucket_base[lane] = prefix_scan_u32_256(lane, count) - count;
            GroupMemoryBarrierWithGroupSync();
        }
        for (uint tile = first_tile; tile < end_tile; ++tile)
        {
            for (uint chunk = 0u; chunk < 8u; ++chunk)
                step_radix_lanes_by_key[chunk][lane] = 0u;
            GroupMemoryBarrierWithGroupSync();

            uint position = tile * size + lane;
            uint row = 0u;
            uint key = 0u;
            uint chunk = lane / 32u;
            uint bit = 1u << (lane % 32u);
            bool active = position < rows;
            if (active)
            {
                row = digit == 0u ? position :
                    source_is_order ? order[position] : temporary[position];
                key = TKey.digit(row, digit);
                InterlockedOr(step_radix_lanes_by_key[chunk][key], bit);
            }
            GroupMemoryBarrierWithGroupSync();

            // Count earlier positions with this digit. The masks use
            // consecutive local IDs and work with any hardware subgroup size.
            if (active)
            {
                uint rank = countbits(step_radix_lanes_by_key[chunk][key] & (bit - 1u));
                for (uint prior = 0u; prior < chunk; ++prior)
                    rank += countbits(step_radix_lanes_by_key[prior][key]);
                uint carry = program.groups > 1u ? histogram[group_slot + key] : 0u;
                uint destination = step_radix_bucket_base[key] + carry
                    + histogram[tile * size + key] + rank;
                if (source_is_order) temporary[destination] = row;
                else order[destination] = row;
            }
            GroupMemoryBarrierWithGroupSync();
        }
        if (digit + 1u < digits && !step_barrier(program)) return false;
    }
    return true;
}
