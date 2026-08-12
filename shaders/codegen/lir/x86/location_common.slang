import codegen.lowering_ir;

bool x86_location_is_register(uint location)
{
    return location != X86_LOCATION_INVALID &&
        (location & X86_LOCATION_REGISTER) != 0u;
}

uint x86_location_payload(uint location)
{
    return location & X86_LOCATION_PAYLOAD_MASK;
}

uint x86_move32_to_fixed_bytes(uint location, uint fixed_register)
{
    if (!x86_location_is_register(location)) return 6u;
    uint source = x86_location_payload(location);
    if (source == fixed_register) return 0u;
    return source >= 8u || fixed_register >= 8u ? 3u : 2u;
}

uint x86_move32_from_fixed_bytes(uint fixed_register, uint location)
{
    if (!x86_location_is_register(location)) return 6u;
    uint destination = x86_location_payload(location);
    if (destination == fixed_register) return 0u;
    return destination >= 8u || fixed_register >= 8u ? 3u : 2u;
}

uint x86_move64_to_fixed_bytes(uint location, uint fixed_register)
{
    if (!x86_location_is_register(location)) return 7u;
    return x86_location_payload(location) == fixed_register ? 0u : 3u;
}

uint x86_move64_from_fixed_bytes(uint fixed_register, uint location)
{
    if (!x86_location_is_register(location)) return 7u;
    return x86_location_payload(location) == fixed_register ? 0u : 3u;
}

uint x86_binary_opcode_bytes(uint operation, uint type_id)
{
    if (operation == X86_LIR_BINARY_MUL_I32) return 3u;
    bool is_unsigned = type_id == 4u || type_id == 6u;
    if (operation == X86_LIR_BINARY_DIV_I32)
        return is_unsigned ? 4u : 3u;
    if (operation == X86_LIR_BINARY_REM_I32)
        return is_unsigned ? 6u : 5u;
    return 2u;
}

uint x86_saved_gpr_count(uint mask)
{
    // R15 is reserved for the process initial-stack pointer used by the
    // native host-runtime ABI. It must never become a user value location.
    return countbits(mask & ((1u << 3u) | (1u << 12u) |
        (1u << 13u) | (1u << 14u)));
}
