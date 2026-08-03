
module utils;

import byte_packing;
import gpu_index;

public static const uint HIGH_BIT = 0x8000u;
public static const uint PF_EMIT = 1u << 0;
public static const uint PF_EOF = 1u << 1;
public static const uint PF_KEEP_EMIT = 1u << 2;
public static const uint PF_KEEP_EOF = 1u << 3;

public bool is_highest_bit_set(uint value)
{
    return (value & HIGH_BIT) != 0u;
}

public uint load_byte_at(ByteAddressBuffer buf, uint i)
{
    return byte_address_load_u8(buf, i);
}

public uint load_u16_packed(StructuredBuffer<uint> buf, uint idx)
{
    uint w = buf[idx >> 1];
    return (idx & 1u) == 0u ? unpack_u16_pair_low(w) : unpack_u16_pair_high(w);
}

public uint2 seeds_from_flags(uint f)
{
    uint emit = (f & PF_EMIT) != 0u ? 1u : 0u;
    uint eof = (f & PF_EOF) != 0u ? 1u : 0u;

    uint keep_emit = (f & PF_KEEP_EMIT) != 0u ? 1u : 0u;
    uint keep_eof = (f & PF_KEEP_EOF) != 0u ? 1u : 0u;

    uint all_seed = emit + eof;
    uint keep_seed = emit * keep_emit + eof * keep_eof;
    return uint2(all_seed, keep_seed);
}

public uint any_end_from_flags(uint f)
{
    return ((f & (PF_EMIT | PF_EOF)) != 0u) ? 1u : 0u;
}

public uint kept_any_from_flags(uint f)
{
    uint emit_kept = ((f & PF_EMIT) != 0u && (f & PF_KEEP_EMIT) != 0u) ? 1u : 0u;
    uint eof_kept = ((f & PF_EOF) != 0u && (f & PF_KEEP_EOF) != 0u) ? 1u : 0u;
    return (emit_kept | eof_kept);
}
