public struct U32Interval
{
    public uint start;
    public uint end;
}

public U32Interval interval_u32(uint start, uint end)
{
    U32Interval interval;
    interval.start = start;
    interval.end = end;
    return interval;
}

public bool interval_u32_valid(U32Interval interval, uint invalid)
{
    return interval.start != invalid &&
           interval.end != invalid &&
           interval.start <= interval.end;
}

public bool interval_u32_overlaps(U32Interval left, U32Interval right, uint invalid)
{
    return interval_u32_valid(left, invalid) &&
           interval_u32_valid(right, invalid) &&
           left.start <= right.end &&
           right.start <= left.end;
}

public bool interval_u32_contains_point(U32Interval interval, uint point, uint invalid)
{
    return interval_u32_valid(interval, invalid) &&
           point >= interval.start &&
           point <= interval.end;
}

public bool interval_u32_strictly_contains_point(
    U32Interval interval,
    uint point,
    uint invalid)
{
    return interval_u32_valid(interval, invalid) &&
           point > interval.start &&
           point < interval.end;
}

public U32Interval interval_u32_extend_end(U32Interval interval, uint point)
{
    interval.end = max(interval.end, point);
    return interval;
}
