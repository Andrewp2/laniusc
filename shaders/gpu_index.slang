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

public uint row_major_slot(uint row, uint stride, uint column)
{
    return row * stride + column;
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
