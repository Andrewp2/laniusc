import shared.collectives.prefix_scan;
import shared.collectives.step_program;

public interface IStepProgramRadixKey
{
    static uint digit(uint row, uint step);
}

groupshared uint step_radix_buckets[8][256];
groupshared uint step_radix_bucket_base[256];

// Each workgroup owns a consecutive range of positions. It counts the
// range's digits in shared memory. Scatter walks that range in position
// order and carries each bucket's write offset from one tile to the next.
// histogram needs program.groups * 256 words. bucket_total needs 256.
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
    if (rows == 0u) return true;

    const uint size = STEP_PROGRAM_GROUP_LANES;
    uint lane = program.lane % size;
    uint group = program.lane / size;
    uint tiles = 1u + (rows - 1u) / size;
    uint tiles_per_group = 1u + (tiles - 1u) / program.groups;
    uint active_groups = 1u + (tiles - 1u) / tiles_per_group;
    uint first_tile = group * tiles_per_group;
    uint end_tile = min(tiles, first_tile + tiles_per_group);
    uint chunk = lane / 32u;
    uint bit = 1u << (lane % 32u);

    // Start on the side that leaves the last digit in order.
    for (uint digit = 0u; digit < digits; ++digit)
    {
        bool source_is_order = ((digits - digit) & 1u) == 0u;
        uint count = 0u;
        if (group < active_groups)
        {
            [unroll]
            for (uint shard = 0u; shard < 8u; ++shard)
                step_radix_buckets[shard][lane] = 0u;
            GroupMemoryBarrierWithGroupSync();
            for (uint position = first_tile * size + lane;
                 position < min(end_tile * size, rows); position += size)
            {
                uint row = digit == 0u ? position :
                    source_is_order ? order[position] : temporary[position];
                InterlockedAdd(step_radix_buckets[chunk][TKey.digit(row, digit)], 1u);
            }
            GroupMemoryBarrierWithGroupSync();

            [unroll]
            for (uint shard = 0u; shard < 8u; ++shard)
                count += step_radix_buckets[shard][lane];
            histogram[group * size + lane] = count;
        }
        if (!step_barrier(program)) return false;

        if (program.groups > 1u)
        {
            // Give each of up to eight workgroups a consecutive range of
            // buckets. Each lane scans one bucket across the active groups.
            uint buckets_per_group = 1u + (size - 1u) / min(program.groups, 8u);
            uint bucket = group * buckets_per_group + lane;
            if (lane < buckets_per_group && bucket < size)
            {
                uint sum = 0u;
                for (uint group_i = 0u; group_i < active_groups; ++group_i)
                {
                    uint slot = group_i * size + bucket;
                    uint group_count = histogram[slot];
                    histogram[slot] = sum;
                    sum += group_count;
                }
                bucket_total[bucket] = sum;
            }
            if (!step_barrier(program)) return false;
            if (group < active_groups) count = bucket_total[lane];
        }

        if (group < active_groups)
        {
            uint carry = program.groups > 1u ? histogram[group * size + lane] : 0u;
            step_radix_bucket_base[lane] = prefix_scan_u32_256(lane, count) - count + carry;
            GroupMemoryBarrierWithGroupSync();
            for (uint tile = first_tile; tile < end_tile; ++tile)
            {
                [unroll]
                for (uint shard = 0u; shard < 8u; ++shard)
                    step_radix_buckets[shard][lane] = 0u;
                GroupMemoryBarrierWithGroupSync();

                uint position = tile * size + lane;
                uint row = 0u;
                uint key = 0u;
                bool active = position < rows;
                if (active)
                {
                    row = digit == 0u ? position :
                        source_is_order ? order[position] : temporary[position];
                    key = TKey.digit(row, digit);
                    InterlockedOr(step_radix_buckets[chunk][key], bit);
                }
                GroupMemoryBarrierWithGroupSync();

                // Count equal keys in earlier positions. The masks are in
                // local lane order and do not depend on the subgroup size.
                uint destination = 0u;
                if (active)
                {
                    uint rank = countbits(step_radix_buckets[chunk][key] & (bit - 1u));
                    for (uint prior = 0u; prior < chunk; ++prior)
                        rank += countbits(step_radix_buckets[prior][key]);
                    destination = step_radix_bucket_base[key] + rank;
                }
                uint tile_count = 0u;
                [unroll]
                for (uint shard = 0u; shard < 8u; ++shard)
                    tile_count += countbits(step_radix_buckets[shard][lane]);
                GroupMemoryBarrierWithGroupSync();

                step_radix_bucket_base[lane] += tile_count;
                if (active)
                {
                    if (source_is_order) temporary[destination] = row;
                    else order[destination] = row;
                }
            }
        }
        if (digit + 1u < digits && !step_barrier(program)) return false;
    }
    return true;
}
