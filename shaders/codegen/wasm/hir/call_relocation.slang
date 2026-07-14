// Shared direct-call encoding contract for executable and relocatable output.
// Runtime imports retain their compact indices. Calls to Lanius declarations
// use the standard maximally padded five-byte varuint32 representation, and
// the first immediate byte carries a GPU-only marker above the low byte. The
// final module pack masks that marker; object projection consumes it first.

public bool wasm_symbol_call_target(uint target)
{
    return target >= 42u;
}

public uint wasm_call_index_len(uint target)
{
    if (wasm_symbol_call_target(target))
        return 5u;
    for (uint i = 0u; i < 5u; i += 1u)
    {
        target >>= 7u;
        if (target == 0u)
            return i + 1u;
    }
    return 5u;
}

public uint wasm_call_index_byte(uint target, uint byte_i)
{
    if (!wasm_symbol_call_target(target))
    {
        uint value = (target >> (byte_i * 7u)) & 0x7fu;
        if (byte_i + 1u < wasm_call_index_len(target))
            value |= 0x80u;
        return value;
    }
    uint value = (target >> (byte_i * 7u)) & 0x7fu;
    if (byte_i < 4u)
        value |= 0x80u;
    // Marker is deliberately outside the emitted byte. `body_words` stores
    // unpacked u32 values until module packing masks them to eight bits.
    if (byte_i == 0u)
        value |= 0x100u;
    return value;
}
