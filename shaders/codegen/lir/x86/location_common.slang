import primitive_types;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.storage_layout;

bool x86_location_is_register(uint location)
{
    return location != X86_LOCATION_INVALID &&
        (location & X86_LOCATION_REGISTER) != 0u &&
        (location & X86_LOCATION_PAYLOAD_MASK) < 16u;
}

bool x86_location_is_xmm(uint location)
{
    uint payload = location & X86_LOCATION_PAYLOAD_MASK;
    return location != X86_LOCATION_INVALID &&
        (location & X86_LOCATION_REGISTER) != 0u &&
        payload >= 16u && payload < 32u;
}

uint x86_xmm_location(uint xmm)
{
    return X86_LOCATION_REGISTER | (16u + xmm);
}

uint x86_location_xmm(uint location)
{
    return x86_location_payload(location) - 16u;
}

uint x86_location_payload(uint location)
{
    return location & X86_LOCATION_PAYLOAD_MASK;
}

bool x86_alias_uses_64_bits(uint metadata)
{
    return (metadata &
            (X86_LIR_METADATA_AGGREGATE | X86_LIR_METADATA_WIDE)) != 0u ||
        scalar_uses_64bit_gpr(metadata & 0xffu) ||
        ((metadata & X86_LIR_METADATA_STRING_PAIR) != 0u &&
         (metadata & X86_LIR_METADATA_STRING_LEN) == 0u) ||
        ((metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u &&
         (metadata & X86_LIR_METADATA_ARRAY_LEN) == 0u);
}

uint x86_stack_displacement_bytes(uint slot)
{
    // RBP-relative slot zero is -8 and each subsequent slot advances by
    // eight bytes. Slots 0..15 therefore fit the signed disp8 encoding;
    // larger frames retain the general disp32 form.
    return slot < 16u ? 1u : 4u;
}

uint x86_signed_displacement_bytes(uint value)
{
    return value <= 0x7fu || value >= 0xffffff80u ? 1u : 4u;
}

uint x86_packed_i32_displacement(uint base_slot, uint element)
{
    return x86_native_word_displacement(base_slot + 1u) + x86_packed_i32_element_offset(element);
}

uint x86_stack32_operand_bytes(uint slot, uint register)
{
    return (register >= 8u ? 1u : 0u) + 2u +
        x86_stack_displacement_bytes(slot);
}

uint x86_stack64_operand_bytes(uint slot)
{
    return 3u + x86_stack_displacement_bytes(slot);
}

uint x86_move_float_from_gpr_bytes(uint source_gpr, uint location, bool wide)
{
    if (!x86_location_is_xmm(location))
        return wide ? x86_move64_from_fixed_bytes(source_gpr, location)
            : x86_move32_from_fixed_bytes(source_gpr, location);
    return 4u + (wide || x86_location_xmm(location) >= 8u ||
        source_gpr >= 8u ? 1u : 0u);
}

uint x86_move32_to_fixed_bytes(uint location, uint fixed_register)
{
    if (x86_location_is_xmm(location))
        return 4u + (x86_location_xmm(location) >= 8u ||
            fixed_register >= 8u ? 1u : 0u);
    if (!x86_location_is_register(location))
        return x86_stack32_operand_bytes(
            x86_location_payload(location), fixed_register);
    uint source = x86_location_payload(location);
    if (source == fixed_register) return 0u;
    return source >= 8u || fixed_register >= 8u ? 3u : 2u;
}

uint x86_move32_from_fixed_bytes(uint fixed_register, uint location)
{
    if (x86_location_is_xmm(location))
        return 4u + (x86_location_xmm(location) >= 8u ||
            fixed_register >= 8u ? 1u : 0u);
    if (!x86_location_is_register(location))
        return x86_stack32_operand_bytes(
            x86_location_payload(location), fixed_register);
    uint destination = x86_location_payload(location);
    if (destination == fixed_register) return 0u;
    return destination >= 8u || fixed_register >= 8u ? 3u : 2u;
}

uint x86_move64_to_fixed_bytes(uint location, uint fixed_register)
{
    if (!x86_location_is_register(location))
        return x86_stack64_operand_bytes(x86_location_payload(location));
    return x86_location_payload(location) == fixed_register ? 0u : 3u;
}

uint x86_move64_from_fixed_bytes(uint fixed_register, uint location)
{
    if (!x86_location_is_register(location))
        return x86_stack64_operand_bytes(x86_location_payload(location));
    return x86_location_payload(location) == fixed_register ? 0u : 3u;
}

uint x86_saved_gpr_frame_bytes(uint mask, uint first_slot)
{
    uint bytes = 0u;
    uint saved_ordinal = 0u;
    static const uint registers[5] = {3u, 12u, 13u, 14u, 15u};
    for (uint ordinal = 0u; ordinal < 5u; ordinal += 1u)
    {
        uint physical = registers[ordinal];
        if ((mask & (1u << physical)) == 0u) continue;
        bytes += x86_stack64_operand_bytes(first_slot + saved_ordinal);
        saved_ordinal += 1u;
    }
    return bytes;
}

bool x86_lea_add32_supported(uint left, uint right, uint destination)
{
    if (!x86_location_is_register(left) ||
        !x86_location_is_register(right) ||
        !x86_location_is_register(destination))
        return false;
    // RSP/R12 cannot occupy the SIB index field. Addition is commutative, so
    // either operand may become the base unless both encode that register.
    return !((x86_location_payload(left) & 7u) == 4u &&
             (x86_location_payload(right) & 7u) == 4u);
}

bool x86_lea_add32_preferred(uint left, uint right, uint destination)
{
    // When the result already aliases either operand, an ordinary two-operand
    // ADD is one byte shorter. LEA wins when it avoids a setup move.
    return destination != left && destination != right &&
        x86_lea_add32_supported(left, right, destination);
}

bool x86_direct_binary32_supported(uint operation)
{
    return operation == X86_LIR_BINARY_ADD_I32 ||
        operation == X86_LIR_BINARY_SUB_I32 ||
        operation == X86_LIR_BINARY_MUL_I32 ||
        operation == X86_LIR_BINARY_BIT_AND_I32 ||
        operation == X86_LIR_BINARY_BIT_OR_I32 ||
        operation == X86_LIR_BINARY_BIT_XOR_I32 ||
        operation == X86_LIR_BINARY_AND_BOOL ||
        operation == X86_LIR_BINARY_OR_BOOL;
}

bool x86_binary32_commutative(uint operation)
{
    return operation != X86_LIR_BINARY_SUB_I32;
}

bool x86_immediate_fits_i8(uint value)
{
    return value <= 127u || value >= 0xffffff80u;
}

bool x86_binary_immediate_identity(uint operation, uint immediate)
{
    return ((operation == X86_LIR_BINARY_ADD_I32 ||
             operation == X86_LIR_BINARY_SUB_I32 ||
             operation == X86_LIR_BINARY_BIT_OR_I32 ||
             operation == X86_LIR_BINARY_BIT_XOR_I32 ||
             operation == X86_LIR_BINARY_OR_BOOL ||
             operation == X86_LIR_BINARY_SHL_I32 ||
             operation == X86_LIR_BINARY_SHR_I32) && immediate == 0u) ||
        ((operation == X86_LIR_BINARY_MUL_I32 ||
          operation == X86_LIR_BINARY_AND_BOOL) && immediate == 1u) ||
        (operation == X86_LIR_BINARY_BIT_AND_I32 &&
         immediate == 0xffffffffu);
}

bool x86_multiply_immediate_shift(uint operation, uint immediate,
                                  out uint shift)
{
    bool power_of_two = immediate > 1u &&
        (immediate & (immediate - 1u)) == 0u;
    shift = power_of_two ? countbits(immediate - 1u) : 0u;
    return operation == X86_LIR_BINARY_MUL_I32 && power_of_two;
}

bool x86_multiply_immediate_negate(uint operation, uint immediate)
{
    return operation == X86_LIR_BINARY_MUL_I32 && immediate == 0xffffffffu;
}

bool x86_multiply_immediate_lea_scale(uint operation, uint immediate,
                                      uint source, uint destination,
                                      out uint scale)
{
    scale = immediate == 2u ? 0u : immediate == 3u ? 1u :
        immediate == 5u ? 2u : 3u;
    return operation == X86_LIR_BINARY_MUL_I32 &&
        (immediate == 2u || immediate == 3u ||
         immediate == 5u || immediate == 9u) &&
        x86_location_is_register(source) &&
        x86_location_is_register(destination) &&
        (x86_location_payload(source) & 7u) != 4u;
}

bool x86_add_sub_immediate_lea(uint operation, uint immediate, uint source,
                               uint destination, out uint displacement)
{
    displacement = operation == X86_LIR_BINARY_SUB_I32
        ? 0u - immediate : immediate;
    return (operation == X86_LIR_BINARY_ADD_I32 ||
            operation == X86_LIR_BINARY_SUB_I32) &&
        x86_location_is_register(source) &&
        x86_location_is_register(destination) &&
        source != destination;
}

bool x86_binary_immediate_inc_dec(uint operation, uint immediate,
                                  uint source, uint destination,
                                  out bool decrement)
{
    bool add_one = operation == X86_LIR_BINARY_ADD_I32 && immediate == 1u;
    bool add_negative_one = operation == X86_LIR_BINARY_ADD_I32 &&
        immediate == 0xffffffffu;
    bool subtract_one = operation == X86_LIR_BINARY_SUB_I32 && immediate == 1u;
    bool subtract_negative_one = operation == X86_LIR_BINARY_SUB_I32 &&
        immediate == 0xffffffffu;
    decrement = add_negative_one || subtract_one;
    return (add_one || add_negative_one ||
            subtract_one || subtract_negative_one) &&
        source == destination && x86_location_is_register(destination);
}

uint x86_power_of_two_shift(uint divisor)
{
    uint shift = 0u;
    while ((divisor >> shift) != 1u) shift += 1u;
    return shift;
}

bool x86_const_pow2_binary(uint operation)
{
    return operation == X86_LIR_BINARY_DIV_CONST_POW2_I32 ||
        operation == X86_LIR_BINARY_REM_CONST_POW2_I32;
}

struct X86SignedDivisionMagic
{
    uint multiplier;
    uint shift;
    bool add_numerator;
};

X86SignedDivisionMagic x86_signed_division_magic(uint divisor)
{
    // LLVM's SignedDivisionByConstantInfo implementation of Hacker's
    // Delight chapter 10, specialized to a positive 32-bit divisor.
    uint signed_min = 0x80000000u;
    uint anc = signed_min - 1u - signed_min % divisor;
    uint p = 31u;
    uint q1 = signed_min / anc;
    uint r1 = signed_min % anc;
    uint q2 = signed_min / divisor;
    uint r2 = signed_min % divisor;
    uint delta;
    do
    {
        p += 1u;
        q1 <<= 1u;
        r1 <<= 1u;
        if (r1 >= anc)
        {
            q1 += 1u;
            r1 -= anc;
        }
        q2 <<= 1u;
        r2 <<= 1u;
        if (r2 >= divisor)
        {
            q2 += 1u;
            r2 -= divisor;
        }
        delta = divisor - r2;
    }
    while (q1 < delta || (q1 == delta && r1 == 0u));

    X86SignedDivisionMagic result;
    result.multiplier = q2 + 1u;
    result.shift = p - 32u;
    result.add_numerator = int(result.multiplier) < 0;
    return result;
}

bool x86_const_signed_binary(uint operation)
{
    return operation == X86_LIR_BINARY_DIV_CONST_I32 ||
        operation == X86_LIR_BINARY_REM_CONST_I32;
}

uint x86_saved_gpr_count(uint mask)
{
    // R15 is reserved for the process initial-stack pointer used by the
    // native host-runtime ABI. It must never become a user value location.
    return countbits(mask & ((1u << 3u) | (1u << 12u) |
        (1u << 13u) | (1u << 14u)));
}

// CALL and CALL_SYMBOL emit the same result moves after their five-byte call.
// Object relocations must use this exact width to find the call's rel32 field;
// a guessed width can patch the preceding prologue instead.
uint x86_call_result_instruction_bytes(uint metadata, uint result_words,
                                       uint result_location)
{
    if ((metadata & 0xffu) == SEMANTIC_LIR_TY_STRING)
        return 5u + x86_move64_from_fixed_bytes(0u, result_location) +
            x86_move32_from_fixed_bytes(2u, result_location + 1u);
    if ((metadata & X86_LIR_METADATA_AGGREGATE) == 0u)
        return 5u + (x86_scalar_float(metadata)
            ? x86_move_float_from_gpr_bytes(0u, result_location, x86_scalar_f64(metadata))
            : scalar_uses_64bit_gpr(metadata & 0xffu)
            ? x86_move64_from_fixed_bytes(0u, result_location)
            : x86_move32_from_fixed_bytes(0u, result_location));
    uint storage_slot = x86_location_payload(result_location) + 1u;
    uint result_store = x86_move64_from_fixed_bytes(0u, result_location);
    if (result_words == 0u)
        return 5u + x86_stack64_operand_bytes(storage_slot) + result_store;
    if (result_words > 2u)
        return x86_stack64_operand_bytes(storage_slot) + 5u + result_store;
    uint bytes = 5u + x86_stack64_operand_bytes(storage_slot);
    if (result_words > 1u)
        bytes += x86_stack64_operand_bytes(storage_slot + 1u);
    return bytes + x86_stack64_operand_bytes(storage_slot) + result_store;
}
