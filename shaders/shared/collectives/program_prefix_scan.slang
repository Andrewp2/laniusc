import shared.collectives.prefix_scan;
import shared.collectives.step_program;

groupshared uint step_program_scan_carry;

// Each lane scans a contiguous range. Only the lane totals participate in the
// workgroup scan. In-place scans are safe because both passes touch only the
// lane's own input range. The caller ends the final step before reusing sums.
public bool step_program_prefix_scan(
    inout StepProgram program,
    uint rows,
    RWStructuredBuffer<uint> input,
    RWStructuredBuffer<uint> prefix,
    RWStructuredBuffer<uint> total,
    RWStructuredBuffer<uint> group_sums)
{
    if (rows == 0u)
    {
        if (program.lane == 0u) total[0u] = 0u;
        return true;
    }

    const uint size = STEP_PROGRAM_GROUP_LANES;
    uint lane = program.lane % size;
    uint group = program.lane / size;
    uint chunk = 1u + (rows - 1u) / program.lanes;
    uint active_groups = 1u + (rows - 1u) / (chunk * size);
    uint first = program.lane * chunk;
    uint end = min(first + chunk, rows);

    uint inclusive = 0u;
    uint sum = 0u;
    if (group < active_groups)
    {
        for (uint row = first; row < end; ++row)
            sum += input[row];
        inclusive = prefix_scan_u32_256(lane, sum);
        if (lane == size - 1u)
        {
            if (active_groups == 1u) total[0u] = inclusive;
            else group_sums[group] = inclusive;
        }
    }

    uint carry = 0u;
    if (active_groups > 1u)
    {
        if (!step_barrier(program)) return false;
        if (group >= active_groups) return true;
        if (group != 0u)
        {
            uint prior = 0u;
            for (uint earlier = lane; earlier < group; earlier += size)
                prior += group_sums[earlier];
            uint prior_inclusive = prefix_scan_u32_256(lane, prior);
            if (lane == size - 1u)
            {
                step_program_scan_carry = prior_inclusive;
                if (group + 1u == active_groups)
                    total[0u] = prior_inclusive + inclusive;
            }
            GroupMemoryBarrierWithGroupSync();
            carry = step_program_scan_carry;
        }
    }

    uint offset = carry + inclusive - sum;
    if (chunk == 1u)
    {
        if (first < rows) prefix[first] = offset;
    }
    else
    {
        for (uint row = first; row < end; ++row)
        {
            uint value = input[row];
            prefix[row] = offset;
            offset += value;
        }
    }
    return true;
}

struct PrefixScanU32x4Add : IPrefixScanOp<uint4>
{
    static uint4 identity() { return uint4(0u); }
    static uint4 combine(uint4 left, uint4 right) { return left + right; }
}

groupshared uint4 step_program_scan_u32x4_values[256];
groupshared uint4 step_program_scan_u32x4_carry;

// Scans four columns together. Totals occupy four consecutive words at
// total_offset, allowing callers to use a range in a status buffer.
public bool step_program_prefix_scan_u32x4(
    inout StepProgram program,
    uint rows,
    RWStructuredBuffer<uint4> input,
    RWStructuredBuffer<uint4> prefix,
    RWStructuredBuffer<uint> total,
    uint total_offset,
    RWStructuredBuffer<uint4> group_sums)
{
    if (rows == 0u)
    {
        if (program.lane == 0u)
            for (uint column = 0u; column < 4u; ++column) total[total_offset + column] = 0u;
        return true;
    }
    const uint size = STEP_PROGRAM_GROUP_LANES;
    uint lane = program.lane % size;
    uint group = program.lane / size;
    uint chunk = 1u + (rows - 1u) / program.lanes;
    uint active_groups = 1u + (rows - 1u) / (chunk * size);
    uint first = program.lane * chunk;
    uint end = min(first + chunk, rows);
    uint4 inclusive = uint4(0u);
    uint4 sum = uint4(0u);

    if (group < active_groups)
    {
        for (uint row = first; row < end; ++row)
            sum += input[row];
        inclusive = prefix_scan_inclusive<uint4, PrefixScanU32x4Add, 256>(
            lane, sum, step_program_scan_u32x4_values);
        if (lane == size - 1u)
        {
            if (active_groups == 1u)
                for (uint column = 0u; column < 4u; ++column) total[total_offset + column] = inclusive[column];
            else group_sums[group] = inclusive;
        }
    }

    uint4 carry = uint4(0u);
    if (active_groups > 1u)
    {
        if (!step_barrier(program)) return false;
        if (group >= active_groups) return true;
        if (group != 0u)
        {
            uint4 prior = lane < group ? group_sums[lane] : uint4(0u);
            uint4 prior_inclusive = prefix_scan_inclusive<uint4, PrefixScanU32x4Add, 256>(
                lane, prior, step_program_scan_u32x4_values);
            if (lane == size - 1u)
            {
                step_program_scan_u32x4_carry = prior_inclusive;
                if (group + 1u == active_groups)
                {
                    uint4 sum_total = prior_inclusive + inclusive;
                    for (uint column = 0u; column < 4u; ++column) total[total_offset + column] = sum_total[column];
                }
            }
            GroupMemoryBarrierWithGroupSync();
            carry = step_program_scan_u32x4_carry;
        }
    }

    uint4 offset = carry + inclusive - sum;
    for (uint row = first; row < end; ++row)
    {
        prefix[row] = offset;
        offset += input[row];
    }
    return true;
}
