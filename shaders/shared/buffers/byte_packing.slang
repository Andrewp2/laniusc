public uint u8_masked(uint value)
{
    return value & 0xffu;
}

public uint packed_u8_shift(uint byte_i)
{
    return (byte_i & 3u) * 8u;
}

public uint packed_u8_at(uint word, uint byte_i)
{
    return u8_masked(word >> packed_u8_shift(byte_i));
}

public uint u32_le_byte(uint value, uint byte_i)
{
    return packed_u8_at(value, byte_i);
}

public uint pack_u8x4(uint b0, uint b1, uint b2, uint b3)
{
    return u8_masked(b0) |
           (u8_masked(b1) << 8u) |
           (u8_masked(b2) << 16u) |
           (u8_masked(b3) << 24u);
}

public uint byte_address_load_u8(ByteAddressBuffer bytes, uint pos)
{
    uint word = bytes.Load(pos & ~3u);
    return packed_u8_at(word, pos & 3u);
}

public uint byte_address_load_u8_bounded(ByteAddressBuffer bytes, uint pos, uint len)
{
    return pos < len ? byte_address_load_u8(bytes, pos) : 0u;
}
