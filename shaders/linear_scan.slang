public void linear_scan_active_clear<let REG_COUNT: int>(
    inout uint active_end[REG_COUNT],
    uint invalid)
{
    for (uint rank = 0u; rank < uint(REG_COUNT); rank += 1u)
        active_end[rank] = invalid;
}

public bool linear_scan_rank_available<let REG_COUNT: int>(
    uint rank,
    uint start,
    inout uint active_end[REG_COUNT],
    uint invalid)
{
    if (rank >= uint(REG_COUNT))
        return false;
    uint end = active_end[rank];
    return end == invalid || end < start;
}

public void linear_scan_activate_rank<let REG_COUNT: int>(
    uint rank,
    uint end,
    inout uint active_end[REG_COUNT])
{
    if (rank < uint(REG_COUNT))
        active_end[rank] = end;
}

public uint linear_scan_first_available_rank<let REG_COUNT: int>(
    uint start,
    uint disallowed_rank_mask,
    inout uint active_end[REG_COUNT],
    uint invalid)
{
    for (uint rank = 0u; rank < uint(REG_COUNT); rank += 1u)
    {
        uint bit = 1u << rank;
        if ((disallowed_rank_mask & bit) != 0u)
            continue;
        if (linear_scan_rank_available<REG_COUNT>(rank, start, active_end, invalid))
            return rank;
    }
    return invalid;
}
