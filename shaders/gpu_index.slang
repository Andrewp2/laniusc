public uint linear_thread_id_2d(uint3 dtid, uint max_groups_x, uint workgroup_size)
{
    return dtid.x + dtid.y * max_groups_x * workgroup_size;
}

public uint linear_dispatch_thread_id_2d(uint3 dtid, uint dispatch_x_stride)
{
    return dtid.x + dtid.y * dispatch_x_stride;
}

public uint linear_group_id_2d(uint3 gid, uint max_groups_x)
{
    return gid.x + gid.y * max_groups_x;
}

public bool index_in_bounds(uint index, uint count)
{
    return index < count;
}

public bool valid_index_or_invalid(uint index, uint count, uint invalid_value)
{
    return index != invalid_value && index < count;
}

public uint4 uint4_fill(uint value)
{
    return uint4(value, value, value, value);
}

public bool uint4_any_not_equal(uint4 value, uint sentinel)
{
    return value.x != sentinel ||
           value.y != sentinel ||
           value.z != sentinel ||
           value.w != sentinel;
}

public bool uint4_all_equal(uint4 value, uint sentinel)
{
    return value.x == sentinel &&
           value.y == sentinel &&
           value.z == sentinel &&
           value.w == sentinel;
}

public uint active_count_from_status(
    uint requested_count,
    StructuredBuffer<uint> status,
    uint count_slot)
{
    return requested_count == 0u ? 0u : min(requested_count, status[count_slot]);
}

public uint active_count_from_rw_status(
    uint requested_count,
    RWStructuredBuffer<uint> status,
    uint count_slot)
{
    return requested_count == 0u ? 0u : min(requested_count, status[count_slot]);
}

public uint row_major_slot(uint row, uint stride, uint column)
{
    return row * stride + column;
}

public T row_major_load<T>(
    StructuredBuffer<T> input,
    uint row,
    uint stride,
    uint column,
    T fallback)
{
    if (!row_major_column_in_bounds(column, stride))
        return fallback;
    return input[row_major_slot(row, stride, column)];
}

public T row_major_load_rw<T>(
    RWStructuredBuffer<T> input,
    uint row,
    uint stride,
    uint column,
    T fallback)
{
    if (!row_major_column_in_bounds(column, stride))
        return fallback;
    return input[row_major_slot(row, stride, column)];
}

public bool row_major_store<T>(
    RWStructuredBuffer<T> output,
    uint row,
    uint stride,
    uint column,
    T value)
{
    if (!row_major_column_in_bounds(column, stride))
        return false;
    output[row_major_slot(row, stride, column)] = value;
    return true;
}

public bool row_major_column_in_bounds(uint column, uint stride)
{
    return column < stride;
}

public bool row_major_slot_in_bounds(
    uint row,
    uint stride,
    uint column,
    uint capacity)
{
    return row_major_column_in_bounds(column, stride) &&
           row_major_slot(row, stride, column) < capacity;
}

public uint encode_nullable_id(uint value, uint invalid_value)
{
    return value == invalid_value ? 0u : value + 1u;
}

public int compare_u32(uint left, uint right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    return 0;
}

public int compare_nullable_id(uint left, uint right, uint invalid_value)
{
    return compare_u32(
        encode_nullable_id(left, invalid_value),
        encode_nullable_id(right, invalid_value));
}

public uint pack_u16_pair(uint low, uint high)
{
    return ((high & 0xffffu) << 16u) | (low & 0xffffu);
}

public uint unpack_u16_pair_low(uint packed)
{
    return packed & 0xffffu;
}

public uint unpack_u16_pair_high(uint packed)
{
    return (packed >> 16u) & 0xffffu;
}
