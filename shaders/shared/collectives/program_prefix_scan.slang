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
