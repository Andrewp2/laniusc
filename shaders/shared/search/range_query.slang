public interface IRowQueryCompare<TKey>
{
    static int compare(uint row, TKey key);
}

public struct QueryRange
{
    public uint begin;
    public uint end;
}

public uint lower_bound_query<TKey, TCompare: IRowQueryCompare<TKey>>(
    uint count,
    TKey key)
{
    uint lo = 0u;
    uint hi = count;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        int cmp = TCompare.compare(mid, key);
        if (cmp < 0)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

public uint upper_bound_query<TKey, TCompare: IRowQueryCompare<TKey>>(
    uint count,
    TKey key)
{
    uint lo = 0u;
    uint hi = count;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        int cmp = TCompare.compare(mid, key);
        if (cmp <= 0)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

public QueryRange equal_range_query<TKey, TCompare: IRowQueryCompare<TKey>>(
    uint count,
    TKey key)
{
    QueryRange range;
    range.begin = lower_bound_query<TKey, TCompare>(count, key);
    range.end = upper_bound_query<TKey, TCompare>(count, key);
    return range;
}

public uint find_equal_query<TKey, TCompare: IRowQueryCompare<TKey>>(
    uint count,
    TKey key)
{
    uint row = lower_bound_query<TKey, TCompare>(count, key);
    return row < count && TCompare.compare(row, key) == 0 ? row : 0xffffffffu;
}
