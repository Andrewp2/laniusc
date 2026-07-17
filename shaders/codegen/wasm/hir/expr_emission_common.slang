// Compact expression-emission records produced once by the metadata pass and
// consumed by every byte scatter. Semantic call resolution deliberately does
// not live here: scatter pipelines only need the resolved target.

import call_relocation;

public static const uint WASM_EXPR_EMISSION_NONE = 0u;
public static const uint WASM_EXPR_EMISSION_CALL = 1u;
public static const uint WASM_EXPR_EMISSION_I32_TO_F32 = 2u;
public static const uint WASM_EXPR_EMISSION_LOCAL_GET = 3u;
public static const uint WASM_EXPR_EMISSION_I32_CONST = 4u;
public static const uint WASM_EXPR_EMISSION_I32_LOAD = 5u;
public static const uint WASM_EXPR_EMISSION_F32_LOAD = 6u;
public static const uint WASM_EXPR_EMISSION_INDEX_I32_LOAD = 7u;
public static const uint WASM_EXPR_EMISSION_INDEX_F32_LOAD = 8u;

public uint2 wasm_expr_no_emission()
{
    return uint2(WASM_EXPR_EMISSION_NONE, 0u);
}

public uint2 wasm_expr_call_emission(uint target)
{
    return uint2(WASM_EXPR_EMISSION_CALL, target);
}

public uint2 wasm_expr_i32_to_f32_emission()
{
    return uint2(WASM_EXPR_EMISSION_I32_TO_F32, 0u);
}

public uint2 wasm_expr_local_get_emission(uint local_index)
{
    return uint2(WASM_EXPR_EMISSION_LOCAL_GET, local_index);
}

public uint2 wasm_expr_i32_const_emission(uint value)
{
    return uint2(WASM_EXPR_EMISSION_I32_CONST, value);
}

public uint2 wasm_expr_load_emission(uint offset, bool f32)
{
    return uint2(
        f32 ? WASM_EXPR_EMISSION_F32_LOAD : WASM_EXPR_EMISSION_I32_LOAD,
        offset);
}

public uint2 wasm_expr_index_load_emission(bool f32)
{
    return uint2(
        f32 ? WASM_EXPR_EMISSION_INDEX_F32_LOAD : WASM_EXPR_EMISSION_INDEX_I32_LOAD,
        0u);
}

uint wasm_expr_u32_leb_byte(uint value, uint byte_i)
{
    if (byte_i >= 5u)
        return 0u;
    uint byte_value = (value >> (byte_i * 7u)) & 0x7fu;
    return byte_i == 4u || (value >> ((byte_i + 1u) * 7u)) == 0u
               ? byte_value
               : byte_value | 0x80u;
}

uint wasm_expr_i32_sleb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current >>= 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done = (current == 0 && !sign_bit_set) ||
                    (current == -1 && sign_bit_set) ||
                    i == 4u;
        if (!done)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (done)
            return 0u;
    }
    return 0u;
}

// Returns true when the compact record owns this node's byte contribution.
// Other expression forms remain the responsibility of the scalar atom/opcode
// helper already used by the consuming scatter.
public bool wasm_expr_emission_byte(uint2 emission, uint byte_i, out uint byte)
{
    byte = 0u;
    if (emission.x == WASM_EXPR_EMISSION_I32_TO_F32)
    {
        byte = byte_i == 0u ? 0xb2u : 0u;
        return true;
    }
    if (emission.x == WASM_EXPR_EMISSION_LOCAL_GET)
    {
        byte = byte_i == 0u
                   ? 0x20u
                   : wasm_expr_u32_leb_byte(emission.y, byte_i - 1u);
        return true;
    }
    if (emission.x == WASM_EXPR_EMISSION_I32_CONST)
    {
        byte = byte_i == 0u
                   ? 0x41u
                   : wasm_expr_i32_sleb_byte(emission.y, byte_i - 1u);
        return true;
    }
    if (emission.x == WASM_EXPR_EMISSION_I32_LOAD ||
        emission.x == WASM_EXPR_EMISSION_F32_LOAD)
    {
        if (byte_i == 0u)
            byte = emission.x == WASM_EXPR_EMISSION_F32_LOAD ? 0x2au : 0x28u;
        else if (byte_i == 1u)
            byte = 2u;
        else
            byte = wasm_expr_u32_leb_byte(emission.y, byte_i - 2u);
        return true;
    }
    if (emission.x == WASM_EXPR_EMISSION_INDEX_I32_LOAD ||
        emission.x == WASM_EXPR_EMISSION_INDEX_F32_LOAD)
    {
        if (byte_i == 0u)
            byte = 0x41u;
        else if (byte_i == 1u)
            byte = 4u;
        else if (byte_i == 2u)
            byte = 0x6cu;
        else if (byte_i == 3u)
            byte = 0x6au;
        else if (byte_i == 4u)
            byte = emission.x == WASM_EXPR_EMISSION_INDEX_F32_LOAD ? 0x2au : 0x28u;
        else if (byte_i == 5u)
            byte = 2u;
        else
            byte = 0u;
        return true;
    }
    if (emission.x != WASM_EXPR_EMISSION_CALL)
        return false;
    if (byte_i == 0u)
        byte = 0x10u;
    else
        byte = wasm_call_index_byte(emission.y, byte_i - 1u);
    return true;
}
