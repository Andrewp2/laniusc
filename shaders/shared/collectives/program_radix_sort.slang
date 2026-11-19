import radix.stable_radix_scatter;
import shared.collectives.prefix_scan;
import shared.collectives.scatter;
import shared.collectives.step_program;

public interface IStepProgramRadixKey
{
    static uint digit(uint row, uint step);
}

groupshared uint step_radix_histogram[256];
groupshared uint step_radix_bucket_base[256];

// Orders row IDs by consecutive low-to-high byte digits. A tile holds 256
// consecutive positions. Prefixing tile histograms in position order and
// ranking equal keys in lane order preserves stability across tiles too.
// histogram needs ceil(rows / 256) * 256 words, and bucket_total needs 256.
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

    // Start on the side that leaves the last digit in order.
    for (uint digit = 0u; digit < digits; ++digit)
    {
        bool source_is_order = ((digits - digit) & 1u) == 0u;
        for (uint tile = group; tile < tiles; tile += program.groups)
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
            histogram[tile * size + lane] = step_radix_histogram[lane];
            GroupMemoryBarrierWithGroupSync();
        }
        if (!step_barrier(program)) return false;

        for (uint bucket = program.lane; bucket < size; bucket += program.lanes)
        {
            uint sum = 0u;
            for (uint tile = 0u; tile < tiles; ++tile)
            {
                uint slot = tile * size + bucket;
                uint count = histogram[slot];
                histogram[slot] = sum;
                sum += count;
            }
            bucket_total[bucket] = sum;
        }
        if (!step_barrier(program)) return false;

        if (group < tiles)
        {
            uint count = bucket_total[lane];
            step_radix_bucket_base[lane] = prefix_scan_u32_256(lane, count) - count;
            GroupMemoryBarrierWithGroupSync();
        }
        for (uint tile = group; tile < tiles; tile += program.groups)
        {
            uint position = tile * size + lane;
            uint row = 0u;
            uint key = SCATTER_INACTIVE_KEY;
            if (position < rows)
            {
                row = digit == 0u ? position :
                    source_is_order ? order[position] : temporary[position];
                key = TKey.digit(row, digit);
            }
            uint local_rank;
            uint sorted_key;
            uint sorted_row;
            stable_radix_sort_byte_rank(lane, key, row, sorted_key, sorted_row, local_rank);
            if (sorted_key != SCATTER_INACTIVE_KEY)
            {
                uint destination = step_radix_bucket_base[sorted_key]
                    + histogram[tile * size + sorted_key] + local_rank;
                if (source_is_order) temporary[destination] = sorted_row;
                else order[destination] = sorted_row;
            }
            GroupMemoryBarrierWithGroupSync();
        }
        if (digit + 1u < digits && !step_barrier(program)) return false;
    }
    return true;
}
