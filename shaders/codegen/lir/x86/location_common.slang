import codegen.lowering_ir;

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
    return (metadata & X86_LIR_METADATA_AGGREGATE) != 0u ||
        (metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER ||
        ((metadata & X86_LIR_METADATA_STRING_PAIR) != 0u &&
         (metadata & X86_LIR_METADATA_STRING_LEN) == 0u);
}

uint x86_stack_displacement_bytes(uint slot)
{
    // RBP-relative slot zero is -8 and each subsequent slot advances by
    // eight bytes. Slots 0..15 therefore fit the signed disp8 encoding;
    // larger frames retain the general disp32 form.
    return slot < 16u ? 1u : 4u;
}

uint x86_stack32_operand_bytes(uint slot, uint register)
{
    return (register >= 8u ? 1u : 0u) + 2u +
        x86_stack_displacement_bytes(slot);
}

uint x86_stack_xmm32_operand_bytes(uint slot)
{
    return 4u + x86_stack_displacement_bytes(slot);
}

uint x86_stack64_operand_bytes(uint slot)
{
    return 3u + x86_stack_displacement_bytes(slot);
}

uint x86_move_f32_to_xmm_bytes(uint location, uint destination_xmm)
{
    if (x86_location_is_xmm(location))
    {
        uint source_xmm = x86_location_xmm(location);
        return source_xmm == destination_xmm ? 0u :
            4u + (source_xmm >= 8u || destination_xmm >= 8u ? 1u : 0u);
    }
    if (x86_location_is_register(location))
        return 4u + (x86_location_payload(location) >= 8u ||
            destination_xmm >= 8u ? 1u : 0u);
    return x86_stack_xmm32_operand_bytes(x86_location_payload(location)) +
        (destination_xmm >= 8u ? 1u : 0u);
}

uint x86_move_f32_from_xmm_bytes(uint source_xmm, uint location)
{
    if (x86_location_is_xmm(location))
    {
        uint destination_xmm = x86_location_xmm(location);
        return destination_xmm == source_xmm ? 0u :
            4u + (destination_xmm >= 8u || source_xmm >= 8u ? 1u : 0u);
    }
    if (x86_location_is_register(location))
        return 4u + (x86_location_payload(location) >= 8u ||
            source_xmm >= 8u ? 1u : 0u);
    return x86_stack_xmm32_operand_bytes(x86_location_payload(location)) +
        (source_xmm >= 8u ? 1u : 0u);
}

uint x86_move_f32_to_gpr_bytes(uint location, uint destination_gpr)
{
    if (!x86_location_is_xmm(location))
        return x86_move32_to_fixed_bytes(location, destination_gpr);
    return 4u + (x86_location_xmm(location) >= 8u ||
        destination_gpr >= 8u ? 1u : 0u);
}

uint x86_move_f32_from_gpr_bytes(uint source_gpr, uint location)
{
    if (!x86_location_is_xmm(location))
        return x86_move32_from_fixed_bytes(source_gpr, location);
    return 4u + (x86_location_xmm(location) >= 8u ||
        source_gpr >= 8u ? 1u : 0u);
}

uint x86_move_f32_between_bytes(uint source, uint destination)
{
    if (source == destination && source != X86_LOCATION_INVALID) return 0u;
    if (x86_location_is_xmm(destination))
        return x86_move_f32_to_xmm_bytes(
            source, x86_location_xmm(destination));
    if (x86_location_is_xmm(source))
        return x86_move_f32_from_xmm_bytes(
            x86_location_xmm(source), destination);
    return x86_move32_between_bytes(source, destination);
}

uint x86_imm_f32_to_location_bytes(uint value, uint destination)
{
    return (value == 0u ? 2u : 5u) +
        x86_move_f32_from_gpr_bytes(0u, destination);
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

uint x86_move32_between_bytes(uint source, uint destination)
{
    if (source == destination && source != X86_LOCATION_INVALID) return 0u;
    bool source_register = x86_location_is_register(source);
    bool destination_register = x86_location_is_register(destination);
    if (source_register && destination_register)
    {
        uint source_gpr = x86_location_payload(source);
        uint destination_gpr = x86_location_payload(destination);
        if (source_gpr == destination_gpr) return 0u;
        return source_gpr >= 8u || destination_gpr >= 8u ? 3u : 2u;
    }
    if (source_register)
        return x86_stack32_operand_bytes(x86_location_payload(destination),
            x86_location_payload(source));
    if (destination_register)
        return x86_stack32_operand_bytes(x86_location_payload(source),
            x86_location_payload(destination));
    return x86_stack32_operand_bytes(x86_location_payload(source), 0u) +
        x86_stack32_operand_bytes(x86_location_payload(destination), 0u);
}

uint x86_move64_between_bytes(uint source, uint destination)
{
    if (source == destination && source != X86_LOCATION_INVALID) return 0u;
    bool source_register = x86_location_is_register(source);
    bool destination_register = x86_location_is_register(destination);
    if (source_register && destination_register)
        return x86_location_payload(source) == x86_location_payload(destination)
            ? 0u : 3u;
    if (source_register)
        return x86_stack64_operand_bytes(x86_location_payload(destination));
    if (destination_register)
        return x86_stack64_operand_bytes(x86_location_payload(source));
    return x86_stack64_operand_bytes(x86_location_payload(source)) +
        x86_stack64_operand_bytes(x86_location_payload(destination));
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

uint x86_imm32_to_location_bytes(uint value, uint destination)
{
    if (value == 0u)
        return x86_location_is_register(destination)
            ? (x86_location_payload(destination) >= 8u ? 1u : 0u) + 2u
            : 2u + x86_stack32_operand_bytes(
                x86_location_payload(destination), 0u);
    if (!x86_location_is_register(destination))
        return 5u + x86_stack32_operand_bytes(
            x86_location_payload(destination), 0u);
    return x86_location_payload(destination) >= 8u ? 6u : 5u;
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

uint x86_lea_add32_bytes(uint left, uint right, uint destination)
{
    uint base = x86_location_payload(left);
    uint index = x86_location_payload(right);
    if ((index & 7u) == 4u)
    {
        uint swap = base;
        base = index;
        index = swap;
    }
    uint prefix = base >= 8u || index >= 8u ||
        x86_location_payload(destination) >= 8u ? 1u : 0u;
    // RBP/R13 requires an explicit zero displacement in mod=01 form.
    return prefix + 3u + ((base & 7u) == 5u ? 1u : 0u);
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

uint x86_lea_scaled32_bytes(uint source, uint destination)
{
    uint source_gpr = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    uint prefix = source_gpr >= 8u || destination_gpr >= 8u ? 1u : 0u;
    return prefix + 3u + ((source_gpr & 7u) == 5u ? 1u : 0u);
}

uint x86_imul_immediate32_bytes(uint immediate, uint source,
                                uint destination)
{
    uint source_payload = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    bool source_register = x86_location_is_register(source);
    uint prefix = destination_gpr >= 8u ||
        (source_register && source_payload >= 8u) ? 1u : 0u;
    return prefix + 2u + (source_register ? 0u :
        x86_stack_displacement_bytes(source_payload)) +
        (x86_immediate_fits_i8(immediate) ? 1u : 4u);
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

uint x86_lea_displaced32_bytes(uint displacement, uint source,
                               uint destination)
{
    uint source_gpr = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    uint prefix = source_gpr >= 8u || destination_gpr >= 8u ? 1u : 0u;
    uint sib = (source_gpr & 7u) == 4u ? 1u : 0u;
    return prefix + 2u + sib +
        (x86_immediate_fits_i8(displacement) ? 1u : 4u);
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

uint x86_inc_dec32_bytes(uint destination)
{
    return (x86_location_payload(destination) >= 8u ? 1u : 0u) + 2u;
}

uint x86_binary_immediate_bytes(uint operation, uint immediate, uint source,
                                uint destination)
{
    if (x86_binary_immediate_identity(operation, immediate))
        return x86_move32_between_bytes(source, destination);
    bool direct = x86_location_is_register(destination);
    uint compute_destination = direct
        ? destination : X86_LOCATION_REGISTER;
    uint store = direct
        ? 0u : x86_move32_from_fixed_bytes(0u, destination);
    uint lea_scale;
    if (x86_multiply_immediate_lea_scale(
            operation, immediate, source, compute_destination, lea_scale))
        return x86_lea_scaled32_bytes(source, compute_destination) + store;
    uint displacement;
    if (x86_add_sub_immediate_lea(
            operation, immediate, source, compute_destination, displacement))
        return x86_lea_displaced32_bytes(
            displacement, source, compute_destination) + store;
    bool decrement;
    if (x86_binary_immediate_inc_dec(
            operation, immediate, source, destination, decrement))
        return x86_inc_dec32_bytes(destination);
    uint multiply_shift;
    bool shift_multiply = x86_multiply_immediate_shift(
        operation, immediate, multiply_shift);
    bool negate_multiply = x86_multiply_immediate_negate(
        operation, immediate);
    if (operation == X86_LIR_BINARY_MUL_I32 &&
        !shift_multiply && !negate_multiply)
        return x86_imul_immediate32_bytes(
            immediate, source, compute_destination) + store;
    if (direct)
    {
        uint prefix = x86_location_payload(destination) >= 8u ? 1u : 0u;
        uint body = operation == X86_LIR_BINARY_SHL_I32 ||
            operation == X86_LIR_BINARY_SHR_I32 ||
            shift_multiply ? 3u : negate_multiply ? 2u :
            x86_immediate_fits_i8(immediate) ? 3u : 6u;
        return x86_move32_between_bytes(source, destination) + prefix + body;
    }
    uint body = operation == X86_LIR_BINARY_SHL_I32 ||
        operation == X86_LIR_BINARY_SHR_I32 ||
        x86_multiply_immediate_shift(operation, immediate, multiply_shift) ? 3u
        : x86_multiply_immediate_negate(operation, immediate) ? 2u
        : x86_immediate_fits_i8(immediate) ? 3u
        : operation == X86_LIR_BINARY_MUL_I32 ? 6u : 5u;
    return x86_move32_to_fixed_bytes(source, 0u) + body +
        x86_move32_from_fixed_bytes(0u, destination);
}

uint x86_compare_immediate_instruction_bytes(uint immediate, uint source)
{
    if (immediate == 0u && x86_location_is_register(source))
        return (x86_location_payload(source) >= 8u ? 1u : 0u) + 2u;
    bool narrow = x86_immediate_fits_i8(immediate);
    return x86_location_is_register(source)
        ? (x86_location_payload(source) >= 8u ? 1u : 0u) +
            (narrow ? 3u : 6u)
        : 2u + x86_stack_displacement_bytes(
            x86_location_payload(source)) + (narrow ? 1u : 4u);
}

uint x86_compare32_instruction_bytes(uint left, uint right)
{
    bool left_register = x86_location_is_register(left);
    bool right_register = x86_location_is_register(right);
    if (left_register && right_register)
        return (x86_location_payload(left) >= 8u ||
                x86_location_payload(right) >= 8u ? 1u : 0u) + 2u;
    if (left_register || right_register)
    {
        uint reg = x86_location_payload(left_register ? left : right);
        uint slot = x86_location_payload(left_register ? right : left);
        return x86_stack32_operand_bytes(slot, reg);
    }
    return x86_move32_to_fixed_bytes(left, 0u) +
        x86_move32_to_fixed_bytes(right, 1u) + 2u;
}

uint x86_test32_instruction_bytes(uint location)
{
    if (!x86_location_is_register(location))
        return x86_move32_to_fixed_bytes(location, 0u) + 2u;
    return (x86_location_payload(location) >= 8u ? 1u : 0u) + 2u;
}

uint x86_compare_immediate_bytes(uint immediate, uint source,
                                 uint destination)
{
    return x86_compare_immediate_instruction_bytes(immediate, source) +
        x86_boolean_result_bytes(destination);
}

uint x86_boolean_result_bytes(uint destination)
{
    if (!x86_location_is_register(destination))
        return 6u + x86_move32_from_fixed_bytes(0u, destination);
    return 6u + (x86_location_payload(destination) >= 4u ? 2u : 0u);
}

uint x86_direct_unary32_bytes(uint operation, uint source, uint destination)
{
    if (!x86_location_is_register(destination)) return 0u;
    uint register = x86_location_payload(destination);
    uint prefix = register >= 8u ? 1u : 0u;
    uint move = x86_move32_between_bytes(source, destination);
    if (operation == X86_LIR_UNARY_NEG_I32)
        return move + prefix + 2u;
    if (operation == X86_LIR_UNARY_NOT_BOOL)
        return move + prefix + 2u + x86_boolean_result_bytes(destination);
    return 0u;
}

uint x86_direct_binary32_opcode_bytes(uint operation, uint right,
                                      uint destination)
{
    uint destination_gpr = x86_location_payload(destination);
    bool right_register = x86_location_is_register(right);
    uint prefix = destination_gpr >= 8u ||
        (right_register && x86_location_payload(right) >= 8u) ? 1u : 0u;
    uint opcode = operation == X86_LIR_BINARY_MUL_I32 ? 3u : 2u;
    return prefix + opcode + (right_register ? 0u :
        x86_stack_displacement_bytes(x86_location_payload(right)));
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

uint x86_const_pow2_binary_bytes(uint operation, uint divisor, uint type_id,
                                 uint source, uint destination)
{
    if (operation == X86_LIR_BINARY_DIV_CONST_POW2_I32 && divisor == 1u)
        return x86_move32_between_bytes(source, destination);
    if (operation == X86_LIR_BINARY_REM_CONST_POW2_I32 && divisor == 1u)
        return x86_imm32_to_location_bytes(0u, destination);
    bool is_unsigned = type_id == 4u || type_id == 6u;
    if (x86_location_is_register(destination))
    {
        uint register = x86_location_payload(destination);
        uint prefix = register >= 8u ? 1u : 0u;
        uint move = x86_move32_between_bytes(source, destination);
        if (is_unsigned)
        {
            uint immediate = divisor - 1u;
            return move + prefix +
                (operation == X86_LIR_BINARY_DIV_CONST_POW2_I32 ||
                 x86_immediate_fits_i8(immediate) ? 3u : 6u);
        }
        uint sign_correction = (register >= 8u ? 3u : 2u) +
            3u + 3u + prefix + 2u;
        uint finish = operation == X86_LIR_BINARY_DIV_CONST_POW2_I32
            ? prefix + 3u
            : prefix + (x86_immediate_fits_i8(divisor - 1u) ? 3u : 6u) +
                prefix + 2u;
        return move + sign_correction + finish;
    }
    uint body = is_unsigned
        ? operation == X86_LIR_BINARY_DIV_CONST_POW2_I32 ? 3u : 5u
        : operation == X86_LIR_BINARY_DIV_CONST_POW2_I32 ? 13u : 17u;
    return x86_move32_to_fixed_bytes(source, 0u) + body +
        x86_move32_from_fixed_bytes(0u, destination);
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

uint x86_const_signed_binary_bytes(uint operation, uint divisor, uint source,
                                   uint destination)
{
    X86SignedDivisionMagic magic = x86_signed_division_magic(divisor);
    uint body = 21u + (magic.add_numerator ? 2u : 0u) +
        (magic.shift != 0u ? 3u : 0u);
    if (operation == X86_LIR_BINARY_REM_CONST_I32)
        return x86_move32_to_fixed_bytes(source, 1u) + body + 8u +
            x86_move32_from_fixed_bytes(1u, destination);
    return x86_move32_to_fixed_bytes(source, 1u) + body +
        x86_move32_from_fixed_bytes(0u, destination);
}

uint x86_saved_gpr_count(uint mask)
{
    // R15 is reserved for the process initial-stack pointer used by the
    // native host-runtime ABI. It must never become a user value location.
    return countbits(mask & ((1u << 3u) | (1u << 12u) |
        (1u << 13u) | (1u << 14u)));
}
