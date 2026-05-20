public bool bitset32_valid_bit(uint bit)
{
    return bit < 32u;
}

public uint bitset32_single(uint bit)
{
    return bitset32_valid_bit(bit) ? (1u << bit) : 0u;
}

public uint bitset32_insert(uint mask, uint bit)
{
    return mask | bitset32_single(bit);
}

public uint bitset32_remove(uint mask, uint bit)
{
    return bitset32_valid_bit(bit) ? (mask & ~(1u << bit)) : mask;
}

public bool bitset32_contains(uint mask, uint bit)
{
    return bitset32_valid_bit(bit) && ((mask & bitset32_single(bit)) != 0u);
}

public bool bitset32_intersects(uint left, uint right)
{
    return (left & right) != 0u;
}

public uint bitset32_union(uint left, uint right)
{
    return left | right;
}

public uint bitset32_intersection(uint left, uint right)
{
    return left & right;
}

public uint bitset32_count(uint mask)
{
    return countbits(mask);
}

public uint bitset32_prefix(uint bit_count)
{
    if (bit_count == 0u)
        return 0u;
    if (bit_count >= 32u)
        return 0xffffffffu;
    return (1u << bit_count) - 1u;
}

public bool bitset32_contains_all(uint mask, uint required)
{
    return (mask & required) == required;
}

public bool bitset32_full_below(uint mask, uint bit_count)
{
    return bitset32_contains_all(mask, bitset32_prefix(bit_count));
}

public uint bitset32_first_set(uint mask, uint invalid)
{
    [loop]
    for (uint bit = 0u; bit < 32u; bit += 1u)
    {
        if (bitset32_contains(mask, bit))
            return bit;
    }
    return invalid;
}

public uint bitset32_first_clear_below(uint mask, uint bit_count, uint invalid)
{
    uint limit = min(bit_count, 32u);
    [loop]
    for (uint bit = 0u; bit < limit; bit += 1u)
    {
        if (!bitset32_contains(mask, bit))
            return bit;
    }
    return invalid;
}
