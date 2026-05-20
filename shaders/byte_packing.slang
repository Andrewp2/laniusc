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

public uint replace_packed_u8(uint word, uint byte_i, uint value)
{
    uint shift = packed_u8_shift(byte_i);
    uint mask = 0xffu << shift;
    return (word & ~mask) | (u8_masked(value) << shift);
}

public uint packed_u8_load(StructuredBuffer<uint> words, uint pos)
{
    return packed_u8_at(words[pos / 4u], pos & 3u);
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

public void packed_u8_store(RWStructuredBuffer<uint> words, uint pos, uint value)
{
    uint word_i = pos / 4u;
    words[word_i] = replace_packed_u8(words[word_i], pos & 3u, value);
}

public uint packed_u8_word_from_unpacked(
    StructuredBuffer<uint> bytes,
    uint pos,
    uint len)
{
    uint b0 = pos + 0u < len ? bytes[pos + 0u] : 0u;
    uint b1 = pos + 1u < len ? bytes[pos + 1u] : 0u;
    uint b2 = pos + 2u < len ? bytes[pos + 2u] : 0u;
    uint b3 = pos + 3u < len ? bytes[pos + 3u] : 0u;
    return pack_u8x4(b0, b1, b2, b3);
}
