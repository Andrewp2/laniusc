import range_query;

public interface ISortedJoinLeftKey<TKey>
{
    static bool make_key(uint left_row, out TKey key);
}

public interface ISortedJoinValue<TValue>
{
    static TValue invalid_value();
    static TValue row_value(uint right_row);
}

public bool sorted_join_find_key_row<
    TKey,
    TCompare: IRowQueryCompare<TKey>>(
    uint right_count,
    TKey key,
    uint invalid,
    out uint right_row)
{
    right_row = find_equal_query<TKey, TCompare>(right_count, key);
    if (right_row == invalid || right_row >= right_count)
        return false;
    return true;
}

public bool sorted_join_find_left_row<
    TKey,
    TLeft: ISortedJoinLeftKey<TKey>,
    TCompare: IRowQueryCompare<TKey>>(
    uint left_row,
    uint right_count,
    uint invalid,
    out uint right_row)
{
    TKey key;
    right_row = invalid;
    if (!TLeft.make_key(left_row, key))
        return false;
    return sorted_join_find_key_row<TKey, TCompare>(
        right_count,
        key,
        invalid,
        right_row);
}

public bool sorted_join_project_key<
    TKey,
    TValue,
    TCompare: IRowQueryCompare<TKey>,
    TProject: ISortedJoinValue<TValue>>(
    uint right_count,
    TKey key,
    uint invalid,
    out TValue value)
{
    value = TProject.invalid_value();
    uint right_row;
    if (!sorted_join_find_key_row<TKey, TCompare>(
            right_count,
            key,
            invalid,
            right_row))
        return false;
    value = TProject.row_value(right_row);
    return true;
}

public TValue sorted_join_project_key_or_invalid<
    TKey,
    TValue,
    TCompare: IRowQueryCompare<TKey>,
    TProject: ISortedJoinValue<TValue>>(
    uint right_count,
    TKey key,
    uint invalid)
{
    TValue value;
    sorted_join_project_key<TKey, TValue, TCompare, TProject>(
        right_count,
        key,
        invalid,
        value);
    return value;
}

public bool sorted_join_project_left<
    TKey,
    TValue,
    TLeft: ISortedJoinLeftKey<TKey>,
    TCompare: IRowQueryCompare<TKey>,
    TProject: ISortedJoinValue<TValue>>(
    uint left_row,
    uint right_count,
    uint invalid,
    out TValue value)
{
    value = TProject.invalid_value();
    TKey key;
    if (!TLeft.make_key(left_row, key))
        return false;
    return sorted_join_project_key<TKey, TValue, TCompare, TProject>(
        right_count,
        key,
        invalid,
        value);
}
