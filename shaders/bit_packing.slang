public uint bit_mask_u32(uint width)
{
    if (width == 0u)
        return 0u;
    if (width >= 32u)
        return 0xffffffffu;
    return (1u << width) - 1u;
}

public uint bitfield_extract_u32(uint word, uint bit_offset, uint width)
{
    return (word >> bit_offset) & bit_mask_u32(width);
}

public uint bitfield_insert_u32(uint word, uint bit_offset, uint width, uint value)
{
    uint mask = bit_mask_u32(width);
    uint shifted_mask = mask << bit_offset;
    return (word & ~shifted_mask) | ((value & mask) << bit_offset);
}

public uint packed_u2_at(uint word, uint field_i)
{
    return bitfield_extract_u32(word, field_i * 2u, 2u);
}

public uint packed_u2_at_offset(uint word, uint first_bit, uint field_i)
{
    return bitfield_extract_u32(word, first_bit + field_i * 2u, 2u);
}

public uint pack_u2x4(uint f0, uint f1, uint f2, uint f3)
{
    return bitfield_insert_u32(
        bitfield_insert_u32(
            bitfield_insert_u32(
                bitfield_insert_u32(0u, 0u, 2u, f0),
                2u,
                2u,
                f1),
            4u,
            2u,
            f2),
        6u,
        2u,
        f3);
}

public uint pack_u2x4_at_offset(uint first_bit, uint f0, uint f1, uint f2, uint f3)
{
    return pack_u2x4(f0, f1, f2, f3) << first_bit;
}
