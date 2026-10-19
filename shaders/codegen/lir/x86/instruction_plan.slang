// The x86-64 body of one target LIR row, as a sequence of encoder micro-ops.
//
// This is the only description of how a row's body (and its implicit function
// footer) is encoded. Byte counting sums the encoded lengths of the plan and
// emission writes the encoded bytes, so the two passes cannot disagree.
// x86_plan(input, step) replays the plan and returns its step-th micro-op;
// callers loop until X86_OP_END. Replay keeps the plan free of per-thread
// arrays, and the long packed-copy loop is indexed in O(1).
//
// The plan is pure: the caller supplies every buffer-derived value in
// X86PlanInput, and emission resolves branch targets, runtime offsets and
// string data afterwards (X86_RESOLVE_*), so counting needs none of them.
import primitive_types;
import native_value_layout;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.storage_layout;
import codegen.lir.x86.location_common;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.encoding;

struct X86PlanInput
{
    X86LirCore core;
    X86LirOperands operands;
    X86LirLocations locations;
    uint hidden_sret_slot;   // function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK
    uint saved_first_slot;   // base_frame_slots(function, semantic_function)
    uint saved_mask;
    bool frameless;
    bool stackless;
    uint decl_a;             // declaration_location(operands.a)
    uint decl_target;        // declaration_location(core.result_or_target)
    uint place_slot;         // x86_place_storage_by_token[operands.a].x
    uint callee_row;         // first row of the CALL target; INVALID if unknown
    bool specialized;        // x86_is_specialized_instruction(core, operands)
    bool footer;             // last row of a function without explicit return
    bool skip_body;          // emission only: the row's body writes no bytes
};

static const uint X86_PLAN_INVALID = 0xffffffffu;
static const uint X86_BYTES_ONE_WORD = 1u << 11u;
static const uint X86_BYTES_TWO_WORDS = 2u << 11u;
static const uint X86_BYTES_REL = 1u << 16u;
static const uint X86_BYTES_PREFIX = 1u << 17u;
static const uint X86_REG = X86_LOCATION_REGISTER;

static uint x86_plan_target;
static uint x86_plan_index;
static uint x86_plan_head;
static uint x86_plan_a;
static uint x86_plan_b;
static uint x86_plan_c;

void plan_op(uint head, uint a, uint b, uint c)
{
    if (x86_plan_index == x86_plan_target)
    {
        x86_plan_head = head;
        x86_plan_a = a;
        x86_plan_b = b;
        x86_plan_c = c;
    }
    x86_plan_index += 1u;
}

// `count` little-endian bytes of `bytes`.
void plan_bytes(uint count, uint bytes)
{
    plan_op(X86_OP_BYTES | (count << 8u), bytes, 0u, 0u);
}

// `count` bytes of `bytes`, then a 32-bit word.
void plan_bytes_word(uint count, uint bytes, uint word)
{
    plan_op(X86_OP_BYTES | (count << 8u) | X86_BYTES_ONE_WORD, bytes, word, 0u);
}

void plan_bytes_words(uint count, uint bytes, uint word0, uint word1)
{
    plan_op(X86_OP_BYTES | (count << 8u) | X86_BYTES_TWO_WORDS, bytes, word0, word1);
}

// An optional prefix byte (REX) before `count` bytes.
void plan_prefixed(bool present, uint prefix, uint count, uint bytes)
{
    plan_op(X86_OP_BYTES | (count << 8u) |
        select(present, X86_BYTES_PREFIX | (prefix << 24u), 0u), bytes, 0u, 0u);
}

void plan_prefixed_word(bool present, uint prefix, uint count, uint bytes, uint word)
{
    plan_op(X86_OP_BYTES | (count << 8u) | X86_BYTES_ONE_WORD |
        select(present, X86_BYTES_PREFIX | (prefix << 24u), 0u), bytes, word, 0u);
}

// `count` opcode bytes then a rel32 to a target resolved at emission.
void plan_jump(uint count, uint bytes, uint resolve, uint target)
{
    plan_op(X86_OP_BYTES | (count << 8u) | X86_BYTES_ONE_WORD | (resolve << 13u) |
        X86_BYTES_REL, bytes, target, 0u);
}

void plan_move32(uint source, uint destination)
{
    plan_op(X86_OP_MOVE, source, destination, 0u);
}

void plan_move64(uint source, uint destination)
{
    plan_op(X86_OP_MOVE | (1u << 8u), source, destination, 0u);
}

void plan_move(bool wide, uint source, uint destination)
{
    plan_op(X86_OP_MOVE | select(wide, 1u << 8u, 0u), source, destination, 0u);
}

// Scalar move by checked metadata: floats may use XMM homes; otherwise a
// 64-bit or 32-bit GPR/stack move.
void plan_value_move(bool is_float, bool wide, uint source, uint destination)
{
    plan_op(X86_OP_MOVE | select(wide, 1u << 8u, 0u) | select(is_float, 2u << 8u, 0u),
        source, destination, 0u);
}

void plan_float_move(uint metadata, uint source, uint destination)
{
    plan_value_move(true, x86_scalar_f64(metadata), source, destination);
}

void plan_stack(uint opcode, bool wide, uint reg, uint slot)
{
    plan_op(X86_OP_STACK | (opcode << 8u) | select(wide, 1u << 16u, 0u), reg, slot, 0u);
}

void plan_load64(uint slot, uint reg) { plan_stack(0x8bu, true, reg, slot); }
void plan_store64(uint reg, uint slot) { plan_stack(0x89u, true, reg, slot); }
void plan_lea64(uint reg, uint slot) { plan_stack(0x8du, true, reg, slot); }

// mov dword [rbp + displacement], reg for packed i32 storage.
void plan_store_packed_i32(uint reg, uint base_slot, uint element)
{
    plan_op(X86_OP_STACK | (0x89u << 8u) | (1u << 17u), reg,
        x86_packed_i32_displacement(base_slot, element), 0u);
}

void plan_xmm(bool wide, bool to_xmm, uint xmm, uint location)
{
    plan_op(X86_OP_XMM | select(wide, 1u << 8u, 0u) | select(to_xmm, 2u << 8u, 0u),
        xmm, location, 0u);
}

// mov r32, [reg + byte_offset] with the shortest displacement.
// `reg_rm` is the ModRM byte for a zero displacement (mod 00).
void plan_base_i32_load(uint reg_rm, uint byte_offset)
{
    if (byte_offset == 0u) plan_bytes(2u, 0x8bu | (reg_rm << 8u));
    else if (byte_offset <= 0x7fu)
        plan_bytes(3u, 0x8bu | ((reg_rm | 0x40u) << 8u) | (byte_offset << 16u));
    else plan_bytes_word(2u, 0x8bu | ((reg_rm | 0x80u) << 8u), byte_offset);
}

void plan_restore_registers(uint mask, uint first_slot)
{
    uint saved_ordinal = x86_saved_gpr_count(mask);
    for (uint ordinal = 5u; ordinal > 0u; ordinal -= 1u)
    {
        uint physical = ordinal == 1u ? 3u : ordinal + 10u; // rbx, r12..r15
        if ((mask & (1u << physical)) == 0u) continue;
        saved_ordinal -= 1u;
        plan_load64(first_slot + saved_ordinal, physical);
    }
}

// The shared 48-byte body of an overlapping-safe qword copy from [RDX] to
// [RAX], downward-growing words; the caller has already pushed RDI and RSI.
void plan_memmove_tail(uint words)
{
    uint offset = 0u - (words - 1u) * 8u;
    // cmp rax, rdx; jbe +18; mov rdi, rax; mov rsi, rdx; mov ecx, words
    plan_bytes_words(4u, 0x76d03948u, 0xc7894812u, 0xb9d68948u);
    // std; rep movsq; cld; jmp +23; lea rdi, [rax + offset]
    plan_bytes_words(4u, words, 0xa548f3fdu, 0x4817ebfcu);
    plan_bytes_word(2u, 0xb88du, offset);
    plan_bytes_word(3u, 0xb28d48u, offset); // lea rsi, [rdx + offset]
    plan_bytes_words(1u, 0xb9u, words, 0xa548f3fcu); // mov ecx, words; cld; rep movsq
    plan_bytes(2u, 0x5f5eu); // pop rsi; pop rdi
}

// Indexing owns one address calculation for loads, stores, and value copies.
// A runtime view carries its signed byte stride; fixed arrays retain their
// checked place. Element address in RAX; RCX and RDX are scratch registers.
void plan_index_address(X86PlanInput input, uint words)
{
    X86LirLocations locations = input.locations;
    plan_move64(locations.a, X86_REG);
    if (input.core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
    {
        if ((input.operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
            // mov rcx, [rax-16] (signed byte stride); mov rax, [rax]
            plan_bytes_word(3u, 0x488b48u, 0x008b48f0u);
        else plan_move64(locations.a + 2u, X86_REG | 1u);
        plan_move32(locations.b, X86_REG | 2u);
        // imul rdx, rcx; add rax, rdx
        plan_bytes_word(3u, 0xaf0f48u, 0xd00148d1u);
    }
    else
    {
        plan_move32(locations.b, X86_REG | 1u);
        if ((input.operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
            plan_bytes(4u, 0x88048d48u); // lea rax, [rax + rcx*4]
        else
        {
            plan_bytes_word(3u, 0xc96948u, 0u - words * 8u); // imul rcx, rcx, -stride
            plan_bytes(4u, 0x08048d48u); // lea rax, [rax + rcx]
        }
    }
}

uint plan_setcc_opcode(uint predicate)
{
    return predicate == 0u ? 0x94u : predicate == 1u ? 0x95u :
        predicate == 2u ? 0x9cu : predicate == 3u ? 0x9fu :
        predicate == 4u ? 0x9eu : 0x9du;
}

uint plan_integer_setcc_opcode(uint predicate, uint type_id)
{
    // u32 and char use the carry-based unsigned condition codes. Equality is
    // representation-independent and therefore shared with signed i32.
    if (!scalar_is_unsigned_value(type_id) || predicate <= 1u)
        return plan_setcc_opcode(predicate);
    return predicate == 2u ? 0x92u : predicate == 3u ? 0x97u :
        predicate == 4u ? 0x96u : 0x93u;
}

// One-word aggregates use address-valued operands. Compare the stored word
// (an enum discriminant), not the two unrelated addresses.
void plan_aggregate_word_compare(uint left, uint right)
{
    plan_move64(left, X86_REG);
    plan_move64(right, X86_REG | 1u);
    // mov eax, [rax]; mov ecx, [rcx]; cmp eax, ecx
    plan_bytes_word(2u, 0x008bu, 0xc839098bu);
}

void plan_compare(X86PlanInput input, uint left, uint right_or_immediate)
{
    if ((input.operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
        plan_op(X86_OP_COMPARE_IMMEDIATE32, right_or_immediate, left, 0u);
    else plan_op(X86_OP_COMPARE_LOCATIONS32, left, right_or_immediate, 0u);
}

void plan_footer(X86PlanInput input)
{
    plan_bytes(2u, 0xc031u); // xor eax, eax
    if (input.stackless) plan_bytes(1u, 0x59u); // pop rcx
    else if (!input.frameless)
    {
        plan_restore_registers(input.saved_mask, input.saved_first_slot);
        plan_bytes(1u, 0xc9u); // leave
    }
    plan_bytes(1u, 0xc3u);
}

// Results of CALL and CALL_SYMBOL after the call (and stack release).
void plan_call_result(X86PlanInput input, uint words, uint storage_slot)
{
    uint metadata = input.operands.metadata;
    uint result = input.locations.result;
    if ((metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
    {
        if (words <= 2u)
        {
            // Empty payloads retain an address carrier but write no data bytes.
            for (uint word = 0u; word < words; word++)
                plan_store64(word == 0u ? 0u : 2u, storage_slot + word);
            plan_lea64(0u, storage_slot);
        }
        plan_move64(X86_REG, result);
    }
    else plan_value_move(x86_scalar_float(metadata),
        x86_scalar_float(metadata) ? x86_scalar_f64(metadata)
            : scalar_uses_64bit_gpr(metadata & 0xffu), X86_REG, result);
}

void plan_binary_immediate(X86PlanInput input)
{
    X86LirOperands operands = input.operands;
    X86LirLocations locations = input.locations;
    uint immediate = operands.c;
    if (x86_binary_immediate_identity(operands.a, immediate))
    {
        plan_move32(locations.b, locations.result);
        return;
    }
    bool direct = x86_location_is_register(locations.result);
    uint compute_result = direct ? locations.result : X86_REG;
    uint lea_scale;
    uint displacement;
    bool decrement;
    uint multiply_shift;
    bool shift_multiply = x86_multiply_immediate_shift(operands.a, immediate, multiply_shift);
    bool negate_multiply = x86_multiply_immediate_negate(operands.a, immediate);
    if (x86_multiply_immediate_lea_scale(operands.a, immediate, locations.b,
            compute_result, lea_scale))
        plan_op(X86_OP_LEA_SCALED32, locations.b, compute_result, lea_scale);
    else if (x86_add_sub_immediate_lea(operands.a, immediate, locations.b,
            compute_result, displacement))
        plan_op(X86_OP_LEA_DISPLACED32, displacement, locations.b, compute_result);
    else if (x86_binary_immediate_inc_dec(operands.a, immediate, locations.b,
            locations.result, decrement))
    {
        plan_op(X86_OP_INC_DEC32, locations.result, decrement ? 1u : 0u, 0u);
        return;
    }
    else if (operands.a == X86_LIR_BINARY_MUL_I32 && !shift_multiply && !negate_multiply)
        plan_op(X86_OP_IMUL_IMMEDIATE32, immediate, locations.b, compute_result);
    else
    {
        uint destination = direct ? x86_location_payload(locations.result) : 0u;
        plan_move32(locations.b, direct ? locations.result : X86_REG);
        bool high = destination >= 8u;
        uint d = destination & 7u;
        uint type = operands.metadata & 0xffu;
        if (operands.a == X86_LIR_BINARY_SHL_I32 ||
            operands.a == X86_LIR_BINARY_SHR_I32 || shift_multiply)
        {
            uint extension = operands.a == X86_LIR_BINARY_SHL_I32 || shift_multiply
                ? 0xe0u : type == 4u || type == 6u ? 0xe8u : 0xf8u;
            plan_prefixed(high, 0x41u, 3u, 0xc1u | ((extension | d) << 8u) |
                ((shift_multiply ? multiply_shift : immediate) << 16u));
        }
        else if (negate_multiply)
            plan_prefixed(high, 0x41u, 2u, 0xf7u | ((0xd8u | d) << 8u));
        else if (operands.a == X86_LIR_BINARY_MUL_I32)
        {
            bool narrow = x86_immediate_fits_i8(immediate);
            uint modrm = 0xc0u | (d << 3u) | d;
            if (narrow) plan_prefixed(high, 0x45u, 3u, 0x6bu | (modrm << 8u) | (immediate << 16u));
            else plan_prefixed_word(high, 0x45u, 2u, 0x69u | (modrm << 8u), immediate);
        }
        else
        {
            uint extension =
                operands.a == X86_LIR_BINARY_ADD_I32 ? 0u :
                operands.a == X86_LIR_BINARY_SUB_I32 ? 5u :
                operands.a == X86_LIR_BINARY_BIT_AND_I32 ||
                operands.a == X86_LIR_BINARY_AND_BOOL ? 4u :
                operands.a == X86_LIR_BINARY_BIT_OR_I32 ||
                operands.a == X86_LIR_BINARY_OR_BOOL ? 1u : 6u;
            if (x86_immediate_fits_i8(immediate) || direct)
                plan_op(X86_OP_GROUP1_IMMEDIATE32, extension, destination, immediate);
            else plan_bytes_word(1u, (extension << 3u) | 5u, immediate); // op eax, imm32
        }
    }
    if (!direct) plan_move32(X86_REG, locations.result);
}

void plan_binary_power_of_two(X86PlanInput input)
{
    X86LirOperands operands = input.operands;
    X86LirLocations locations = input.locations;
    uint divisor = operands.c;
    bool division = operands.a == X86_LIR_BINARY_DIV_CONST_POW2_I32;
    if (divisor == 1u)
    {
        if (division) plan_move32(locations.b, locations.result);
        else plan_op(X86_OP_IMM32_TO_LOCATION, 0u, locations.result, 0u);
        return;
    }
    uint shift = x86_power_of_two_shift(divisor);
    uint type = operands.metadata & 0xffu;
    bool is_unsigned = type == 4u || type == 6u;
    bool direct = x86_location_is_register(locations.result);
    uint destination = direct ? x86_location_payload(locations.result) : 0u;
    bool high = destination >= 8u;
    uint d = destination & 7u;
    plan_move32(locations.b, direct ? locations.result : X86_REG);
    if (!is_unsigned)
    {
        // Signed division truncates toward zero. LLVM describes the
        // power-of-two expansion as SRA + SRL + ADD + SRA; remainder uses the
        // same sign correction before applying the mask.
        if (direct) plan_move32(X86_REG | destination, X86_REG | 2u);
        else plan_bytes(2u, 0xc289u); // mov edx, eax
        plan_bytes_word(2u, 0xfac1u, 0xeac11fu | ((32u - shift) << 24u)); // sar edx,31; shr edx,32-shift
        plan_prefixed(high, 0x41u, 2u, 0x01u | ((0xd0u | d) << 8u)); // add dest, edx
    }
    if (division)
        plan_prefixed(high, 0x41u, 3u, 0xc1u |
            (((is_unsigned ? 0xe8u : 0xf8u) | d) << 8u) | (shift << 16u));
    else
    {
        if (direct) plan_op(X86_OP_GROUP1_IMMEDIATE32, 4u, destination, divisor - 1u);
        else plan_bytes_word(1u, 0x25u, divisor - 1u); // and eax, imm32
        if (!is_unsigned) plan_prefixed(high, 0x41u, 2u, 0x29u | ((0xd0u | d) << 8u));
    }
    if (!direct) plan_move32(X86_REG, locations.result);
}

void plan_binary_signed_constant(X86PlanInput input)
{
    X86LirOperands operands = input.operands;
    X86LirLocations locations = input.locations;
    uint divisor = operands.c;
    X86SignedDivisionMagic magic = x86_signed_division_magic(divisor);
    // EAX/ECX/EDX are reserved from allocation. Materialize the numerator
    // directly in ECX, then sign-extend it for the 64-bit magic multiply.
    plan_move32(locations.b, X86_REG | 1u);
    plan_bytes(3u, 0xc16348u); // movsxd rax, ecx
    plan_bytes_word(3u, 0xc06948u, magic.multiplier); // imul rax, rax, magic
    plan_bytes(4u, 0x20e8c148u); // shr rax, 32
    if (magic.add_numerator) plan_bytes(2u, 0xc801u); // add eax, ecx
    if (magic.shift != 0u) plan_bytes(3u, 0xf8c1u | (magic.shift << 16u)); // sar eax, shift
    plan_bytes(4u, 0xeac1c289u); // mov edx, eax; shr edx, ...
    plan_bytes(3u, 0xd0011fu); // ... 31; add eax, edx
    if (operands.a == X86_LIR_BINARY_REM_CONST_I32)
    {
        plan_bytes_word(2u, 0xd069u, divisor); // imul edx, eax, divisor
        plan_bytes(2u, 0xd129u); // sub ecx, edx
        plan_move32(X86_REG | 1u, locations.result);
    }
    else plan_move32(X86_REG, locations.result);
}

void plan_binary(X86PlanInput input)
{
    X86LirOperands operands = input.operands;
    X86LirLocations locations = input.locations;
    if (x86_const_pow2_binary(operands.a)) { plan_binary_power_of_two(input); return; }
    if (x86_const_signed_binary(operands.a)) { plan_binary_signed_constant(input); return; }
    if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u) { plan_binary_immediate(input); return; }
    if (operands.a == X86_LIR_BINARY_ADD_I32 &&
        x86_lea_add32_preferred(locations.b, locations.c, locations.result))
    {
        plan_op(X86_OP_LEA_ADD32, locations.b, locations.c, locations.result);
        return;
    }
    if (x86_location_is_register(locations.result) &&
        x86_direct_binary32_supported(operands.a) &&
        (locations.result != locations.c ||
         locations.result == locations.b ||
         x86_binary32_commutative(operands.a)))
    {
        uint right = locations.c;
        if (locations.result == locations.c && locations.result != locations.b)
            right = locations.b;
        else plan_move32(locations.b, locations.result);
        plan_op(X86_OP_BINARY32, operands.a, right, locations.result);
        return;
    }
    plan_move32(locations.b, X86_REG);
    plan_move32(locations.c, X86_REG | 1u);
    uint type = operands.metadata & 0xffu;
    bool is_unsigned = type == 4u || type == 6u;
    uint operation = operands.a;
    uint bytes = 0u;
    uint count = 2u;
    if (operation == X86_LIR_BINARY_ADD_I32) bytes = 0xc801u;
    else if (operation == X86_LIR_BINARY_SUB_I32) bytes = 0xc829u;
    else if (operation == X86_LIR_BINARY_MUL_I32) { bytes = 0xc1af0fu; count = 3u; }
    else if (operation == X86_LIR_BINARY_DIV_I32 || operation == X86_LIR_BINARY_REM_I32)
    {
        // xor edx, edx; div ecx  |  cdq; idiv ecx
        bytes = is_unsigned ? 0xf1f7d231u : 0xf9f799u;
        count = is_unsigned ? 4u : 3u;
    }
    else if (operation == X86_LIR_BINARY_BIT_AND_I32 || operation == X86_LIR_BINARY_AND_BOOL)
        bytes = 0xc821u;
    else if (operation == X86_LIR_BINARY_BIT_OR_I32 || operation == X86_LIR_BINARY_OR_BOOL)
        bytes = 0xc809u;
    else if (operation == X86_LIR_BINARY_BIT_XOR_I32) bytes = 0xc831u;
    else if (operation == X86_LIR_BINARY_SHL_I32) bytes = 0xe0d3u;
    else if (operation == X86_LIR_BINARY_SHR_I32) bytes = is_unsigned ? 0xe8d3u : 0xf8d3u;
    else count = 0u;
    if (count != 0u) plan_bytes(count, bytes);
    if (operation == X86_LIR_BINARY_REM_I32) plan_bytes(2u, 0xd089u); // mov eax, edx
    plan_move32(X86_REG, locations.result);
}

void plan_ordinary(X86PlanInput input)
{
    X86LirCore core = input.core;
    X86LirOperands operands = input.operands;
    X86LirLocations locations = input.locations;
    uint metadata = operands.metadata;
    uint op = core.op;
    bool is_float = x86_scalar_float(metadata);
    bool f64 = x86_scalar_f64(metadata);
    bool alias64 = x86_alias_uses_64_bits(metadata);
    bool gpr64 = scalar_uses_64bit_gpr(metadata & 0xffu);
    if (op == X86_LIR_OP_IMM_I32)
    {
        if (is_float)
        {
            if (operands.a == 0u) plan_bytes(2u, 0xc031u);
            else plan_bytes_word(1u, 0xb8u, operands.a);
            plan_float_move(metadata, X86_REG, locations.result);
        }
        // A 32-bit immediate write zero-extends to the full GPR, so the same
        // direct form is valid for integers and pointer constants.
        else plan_op(X86_OP_IMM32_TO_LOCATION, operands.a, locations.result, 0u);
    }
    else if (op == X86_LIR_OP_ALIAS || op == X86_LIR_OP_INLINE_RESULT)
    {
        uint component = (metadata &
            (X86_LIR_METADATA_STRING_PAIR | X86_LIR_METADATA_ARRAY_PAIR)) != 0u
            ? operands.c : 0u;
        uint source = op == X86_LIR_OP_ALIAS ? input.decl_a + component : locations.a;
        plan_value_move(is_float, is_float ? f64 : alias64, source, locations.result);
    }
    else if (op == X86_LIR_OP_STORE_LOCAL)
    {
        uint destination = input.decl_a;
        if ((metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            plan_lea64(0u, x86_location_payload(locations.result) + 1u);
            plan_move64(X86_REG, destination);
        }
        else if ((metadata & X86_LIR_METADATA_STRING_PAIR) != 0u)
        {
            plan_move64(locations.b, destination);
            plan_move32(locations.c, destination + 1u);
        }
        else plan_value_move(is_float, is_float ? f64 : gpr64, locations.b, destination);
    }
    else if (op == X86_LIR_OP_AGGREGATE_ADDR)
    {
        plan_lea64(0u, x86_location_payload(locations.result) + 1u);
        plan_move64(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_AGGREGATE_INIT)
    {
        if ((metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
        {
            if ((metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u && operands.b == NATIVE_SLICE_STRIDE)
                plan_bytes_word(3u, 0xc0c748u, operands.a); // mov rax, imm32
            else plan_bytes_word(1u, 0xb8u, operands.a);
        }
        else plan_value_move(is_float, is_float ? f64 : true, locations.a, X86_REG);
        if ((metadata & X86_LIR_METADATA_AGGREGATE) != 0u &&
            (metadata & X86_LIR_METADATA_ARRAY_PAIR) == 0u)
            plan_bytes_word(3u, 0x808b48u, x86_native_word_displacement(operands.b));
        plan_move64(X86_REG, locations.c);
    }
    else if (op == X86_LIR_OP_FIELD_LOAD)
    {
        plan_move64(locations.a, X86_REG);
        bool aggregate = (metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        bool f32 = !aggregate && (metadata & 0xffu) == X86_LIR_TY_FLOAT;
        uint opcode = aggregate ? 0x8du : 0x8bu;
        // [REX.W] mov/lea rax, [rax + disp32]
        plan_prefixed_word(!f32, 0x48u, 2u, opcode | 0x8000u,
            x86_native_word_displacement(operands.b));
        plan_value_move(is_float, is_float ? f64 : true, X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_FIELD_STORE)
    {
        plan_move64(locations.a, X86_REG);
        plan_value_move(is_float, is_float ? f64 : true, locations.c, X86_REG | 1u);
        plan_bytes_word(3u, 0x888948u, x86_native_word_displacement(operands.b));
    }
    else if (op == X86_LIR_OP_BINARY) plan_binary(input);
    else if (op == X86_LIR_OP_COMPARE)
    {
        plan_compare(input, locations.b, (metadata & X86_LIR_METADATA_IMMEDIATE) != 0u
            ? operands.c : locations.c);
        plan_op(X86_OP_BOOLEAN_RESULT,
            plan_integer_setcc_opcode(operands.a, metadata & 0xffu), locations.result, 0u);
    }
    else if (op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        plan_compare(input, locations.a, (metadata & X86_LIR_METADATA_IMMEDIATE) != 0u
            ? operands.b : locations.b);
        uint jcc = (plan_integer_setcc_opcode(core.local_ordinal, metadata & 0xffu) ^ 1u) - 0x10u;
        plan_jump(2u, 0x0fu | (jcc << 8u), X86_RESOLVE_ROW, core.result_or_target);
    }
    else if (op == X86_LIR_OP_SELECT_STORE)
    {
        uint destination = input.decl_target;
        bool register_destination = x86_location_is_register(destination);
        uint selected = register_destination ? x86_location_payload(destination) : 2u;
        plan_move32(locations.result, register_destination ? destination : X86_REG | 2u);
        plan_compare(input, locations.a, (metadata & X86_LIR_METADATA_IMMEDIATE) != 0u
            ? operands.b : locations.b);
        // Loading the true candidate after CMP is safe because MOV preserves
        // flags; CMOV then updates the final declaration register in place.
        plan_move32(locations.c, X86_REG);
        uint cmov = plan_integer_setcc_opcode(core.local_ordinal, metadata & 0xffu) - 0x50u;
        plan_prefixed(selected >= 8u, 0x44u, 3u,
            0x0fu | (cmov << 8u) | ((0xc0u | ((selected & 7u) << 3u)) << 16u));
        if (!register_destination) plan_move32(X86_REG | 2u, destination);
    }
    else if (op == X86_LIR_OP_UNARY &&
        (operands.a == X86_LIR_UNARY_NEG_I32 || operands.a == X86_LIR_UNARY_NOT_BOOL))
    {
        bool negate = operands.a == X86_LIR_UNARY_NEG_I32;
        bool direct = x86_location_is_register(locations.result) &&
            (negate || operands.a == X86_LIR_UNARY_NOT_BOOL);
        plan_move32(locations.b, direct ? locations.result : X86_REG);
        uint destination = direct ? x86_location_payload(locations.result) : 0u;
        uint d = destination & 7u;
        if (negate) plan_prefixed(destination >= 8u, 0x41u, 2u, 0xf7u | ((0xd8u | d) << 8u));
        else
        {
            plan_prefixed(destination >= 8u, 0x45u, 2u, 0x85u | ((0xc0u | (d << 3u) | d) << 8u));
            plan_op(X86_OP_BOOLEAN_RESULT, 0x94u, locations.result, 0u);
        }
        if (!direct && operands.a != X86_LIR_UNARY_NOT_BOOL) plan_move32(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_TRAP) plan_bytes(2u, 0x0b0fu); // ud2
    else if (op == X86_LIR_OP_AGGREGATE_FILL && operands.c != 0u)
    {
        // Slots grow toward lower addresses, so the last of the C slots
        // starting at this row's own is the lowest address. RDI may hold a
        // value; RAX and RCX are row scratch, and DF is clear.
        plan_bytes(1u, 0x57u); // push rdi
        plan_lea64(7u, x86_location_payload(locations.result) + operands.c - 1u);
        plan_bytes_word(1u, 0xb9u, operands.c); // mov ecx, words
        plan_bytes(2u, 0xc031u); // xor eax, eax
        plan_bytes(3u, 0xab48f3u); // rep stosq
        plan_bytes(1u, 0x5fu); // pop rdi
    }
    else if (op == X86_LIR_OP_RETURN || op == X86_LIR_OP_RETURN_VOID)
    {
        if (operands.c != 0u)
        {
            if (operands.c > 2u) plan_load64(input.hidden_sret_slot, 0u);
        }
        else if (operands.a == X86_PLAN_INVALID || op == X86_LIR_OP_RETURN_VOID)
            plan_bytes(2u, 0xc031u);
        else plan_value_move(is_float, is_float ? f64 : gpr64, locations.a, X86_REG);
        plan_restore_registers(input.saved_mask, input.saved_first_slot);
        // pop rcx; ret  |  leave; ret  |  ret
        if (input.stackless) plan_bytes(2u, 0xc359u);
        else if (!input.frameless) plan_bytes(2u, 0xc3c9u);
        else plan_bytes(1u, 0xc3u);
    }
    else if (op == X86_LIR_OP_CALL_ARG)
    {
        bool stack_argument = operands.b >= 6u;
        if (stack_argument && core.local_ordinal != 0u) plan_bytes(4u, 0x08ec8348u); // sub rsp, 8
        uint destination = X86_REG | (stack_argument ? 0u : x86_abi_argument_register(operands.b));
        if ((metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
        {
            if ((metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u && operands.c == NATIVE_SLICE_STRIDE)
            {
                uint reg = x86_location_payload(destination);
                plan_bytes_word(3u, select(reg >= 8u, 0x49u, 0x48u) | 0xc700u |
                    ((0xc0u | (reg & 7u)) << 16u), operands.a);
            }
            else plan_op(X86_OP_IMM32_TO_LOCATION, operands.a, destination, 0u);
        }
        else plan_value_move(is_float, is_float ? f64 :
            (metadata & (X86_LIR_METADATA_AGGREGATE | X86_LIR_METADATA_WIDE)) != 0u,
            locations.a, destination);
        if (stack_argument) plan_bytes(1u, 0x50u); // push rax
    }
    else if (op == X86_LIR_OP_CALL || op == X86_LIR_OP_CALL_SYMBOL)
    {
        bool local = op == X86_LIR_OP_CALL;
        if (local && input.callee_row == X86_PLAN_INVALID) return;
        uint storage_slot = x86_location_payload(locations.result) + 1u;
        uint words = local ? operands.c : x86_symbol_call_result_words(core.local_ordinal);
        uint stack_bytes = local ? core.local_ordinal : x86_symbol_call_stack_bytes(core.local_ordinal);
        if ((metadata & X86_LIR_METADATA_AGGREGATE) != 0u && words > 2u)
            plan_lea64(7u, storage_slot);
        // Object projection relocates the placeholder following an imported E8.
        plan_op(X86_OP_BYTES | (1u << 8u) | X86_BYTES_ONE_WORD |
            select(local, (X86_RESOLVE_ROW << 13u) | X86_BYTES_REL, 0u),
            0xe8u, local ? input.callee_row : 0u, 0u);
        if (stack_bytes != 0u) plan_bytes_word(3u, 0xc48148u, stack_bytes); // add rsp, imm32
        plan_call_result(input, words, storage_slot);
    }
    else if (op == X86_LIR_OP_CALL_HOST && operands.a == HOST_SERVICE_I32_TO_F32)
    {
        // The preceding CALL_ARG row placed the signed i32 in EDI.
        plan_bytes(4u, 0xc72a0ff3u); // cvtsi2ss xmm0, edi
        plan_xmm(false, false, 0u, locations.result);
    }
    else if (op == X86_LIR_OP_CALL_HOST && x86_runtime_service_supported(operands.a))
    {
        plan_jump(1u, 0xe8u, X86_RESOLVE_RUNTIME, x86_runtime_service_offset(operands.a));
        if (x86_runtime_service_has_result(operands.a))
            plan_move(gpr64, X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
    {
        if (operands.c <= 2u)
        {
            if (operands.b == 0u)
            {
                plan_move64(locations.a, X86_REG);
                // Both words share one aggregate address. Read the high word
                // before replacing RAX (which may hold that address) with the
                // low word; the second target row emits no bytes.
                if (operands.c == 2u)
                    plan_bytes_word(3u, 0x908b48u, x86_native_word_displacement(1u));
                plan_bytes(3u, 0x008b48u);
            }
        }
        else
        {
            plan_move64(locations.a, X86_REG);
            plan_load64(input.hidden_sret_slot, 10u);
            if (operands.b == 0u)
                plan_bytes_word(2u, 0x8b48u, 0x0a894908u); // mov rcx,[rax]; mov [r10],rcx
            else
            {
                uint displacement = x86_native_word_displacement(operands.b);
                plan_bytes_word(3u, 0x888b48u, displacement);
                plan_bytes_word(3u, 0x8a8949u, displacement);
            }
        }
    }
    else if (op == X86_LIR_OP_AGGREGATE_COPY_WORD)
    {
        plan_move64(locations.a, X86_REG);
        if (operands.b == 0u) plan_bytes(3u, 0x088b48u);
        else plan_bytes_word(3u, 0x888b48u, x86_native_word_displacement(operands.b));
        plan_move64(X86_REG | 1u, locations.result);
    }
    else if (op == X86_LIR_OP_STRING_ADDR)
    {
        // movabs rax, address of the string's rodata bytes
        plan_op(X86_OP_BYTES | (2u << 8u) | X86_BYTES_TWO_WORDS | (X86_RESOLVE_STRING_ADDR << 13u),
            0xb848u, operands.a, 0u);
        plan_move64(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_STRING_LEN)
    {
        plan_op(X86_OP_BYTES | (1u << 8u) | X86_BYTES_ONE_WORD | (X86_RESOLVE_STRING_LEN << 13u),
            0xb8u, operands.a, 0u);
        plan_move32(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_BRANCH)
    {
        if (operands.a == X86_PLAN_INVALID) plan_jump(1u, 0xe9u, X86_RESOLVE_ROW, operands.b);
        else
        {
            plan_op(X86_OP_TEST_LOCATION32, locations.a, 0u, 0u);
            plan_jump(2u, 0x840fu, X86_RESOLVE_ROW, operands.b);
        }
    }
}

// Arithmetic for the distinct integer widths uses fixed scratch GPRs.
void plan_integer_width_normalize(uint type)
{
    uint bits = scalar_integer_bits(type);
    if (bits != 8u && bits != 16u) return;
    // movsx/movzx eax, al/ax
    plan_bytes(3u, 0x0fu | ((scalar_is_signed_integer(type)
        ? (bits == 8u ? 0xbeu : 0xbfu) : (bits == 8u ? 0xb6u : 0xb7u)) << 8u) | 0xc00000u);
}

// `value as T` with Rust semantics. Integers are extended to 64 bits in RAX by
// their source signedness (narrow values are canonical in 32 bits), then
// truncated by the target's width. Floats round through XMM15, with XMM14 for
// constants. Float-to-integer conversion truncates toward zero, maps NaN to
// zero and saturates at the target's bounds.
void plan_convert(X86PlanInput input)
{
    X86LirLocations locations = input.locations;
    uint source = input.operands.c;
    uint target = input.operands.metadata & 0xffu;
    bool source_f64 = source == SCALAR_F64;
    bool target_f64 = target == SCALAR_F64;
    bool target_float = scalar_is_float(target);
    bool target_wide = scalar_uses_64bit_gpr(target);
    // cvtsi2ss/cvtsi2sd xmm15, r64 with this ModRM; addss/addsd xmm15, xmm15.
    uint to_float_prefix = select(target_f64, 0xf2u, 0xf3u);
    if (scalar_is_float(source))
    {
        plan_xmm(source_f64, true, 15u, locations.b);
        if (target_float)
        {
            // cvtss2sd / cvtsd2ss xmm15, xmm15
            if (source_f64 != target_f64)
                plan_bytes_word(1u, select(source_f64, 0xf2u, 0xf3u), 0xff5a0f45u);
            plan_xmm(target_f64, false, 15u, locations.result);
            return;
        }
        if (!source_f64) plan_bytes_word(1u, 0xf3u, 0xff5a0f45u); // cvtss2sd xmm15, xmm15
        // NaN becomes +0.0: movapd xmm14, xmm15; cmpordsd xmm14, xmm15;
        // andpd xmm15, xmm14.
        plan_bytes_word(1u, 0x66u, 0xf7280f45u);
        plan_bytes_word(2u, 0x45f2u, 0x07f7c20fu);
        plan_bytes_word(1u, 0x66u, 0xfe540f45u);
        uint bits = scalar_integer_bits(target);
        bool is_signed = scalar_is_signed_integer(target);
        if (bits <= 32u)
        {
            // Clamp to [lo, hi], both exact in f64, then truncate. hi is
            // 2^k - 1: exponent 1022 + k and the top k - 1 fraction bits.
            uint k = is_signed ? bits - 1u : bits;
            uint hi_high = ((1022u + k) << 20u) |
                (k > 21u ? 0xfffffu : 0xfffffu & ~((1u << (21u - k)) - 1u));
            uint hi_low = k > 21u ? ~((1u << (53u - k)) - 1u) : 0u;
            uint lo_high = is_signed ? 0x80000000u | ((1023u + k) << 20u) : 0u;
            // movabs rax, lo; movq xmm14, rax; maxsd xmm15, xmm14
            plan_bytes_words(2u, 0xb848u, 0u, lo_high);
            plan_bytes_word(1u, 0x66u, 0xf06e0f4cu);
            plan_bytes_word(1u, 0xf2u, 0xfe5f0f45u);
            // movabs rax, hi; movq xmm14, rax; minsd xmm15, xmm14
            plan_bytes_words(2u, 0xb848u, hi_low, hi_high);
            plan_bytes_word(1u, 0x66u, 0xf06e0f4cu);
            plan_bytes_word(1u, 0xf2u, 0xfe5d0f45u);
            plan_bytes_word(1u, 0xf2u, 0xc72c0f49u); // cvttsd2si rax, xmm15
        }
        else
        {
            // xmm14 = 2^63. Unsigned sources below zero clamp to zero first:
            // xorpd xmm14, xmm14; maxsd xmm15, xmm14.
            if (!is_signed)
            {
                plan_bytes_word(1u, 0x66u, 0xf6570f45u);
                plan_bytes_word(1u, 0xf2u, 0xfe5f0f45u);
            }
            plan_bytes_words(2u, 0xb948u, 0u, 0x43e00000u); // movabs rcx, 2^63
            plan_bytes_word(1u, 0x66u, 0xf16e0f4cu); // movq xmm14, rcx
            plan_bytes_word(1u, 0xf2u, 0xc72c0f49u); // cvttsd2si rax, xmm15
            if (is_signed)
            {
                // Values >= 2^63 produced the indefinite integer; saturate.
                plan_bytes_word(1u, 0x66u, 0xfe2e0f45u); // ucomisd xmm15, xmm14
                plan_bytes_words(2u, 0xb948u, 0xffffffffu, 0x7fffffffu); // movabs rcx, i64::MAX
            }
            else
            {
                // Values >= 2^63 convert x - 2^63 and restore the top bit,
                // which the first conversion's indefinite result supplies.
                plan_bytes_word(1u, 0xf2u, 0xfe5c0f45u); // subsd xmm15, xmm14
                plan_bytes_word(1u, 0xf2u, 0xcf2c0f49u); // cvttsd2si rcx, xmm15
                plan_bytes_word(3u, 0xc28948u, 0x3ffac148u); // mov rdx, rax; sar rdx, 63
                plan_bytes(3u, 0xd12148u); // and rcx, rdx
                plan_bytes(3u, 0xc80948u); // or rax, rcx
                // x >= 2^64 saturates.
                plan_bytes_word(1u, 0x66u, 0xfe2e0f45u); // ucomisd xmm15, xmm14
                plan_bytes_word(3u, 0xc1c748u, 0xffffffffu); // mov rcx, -1
            }
            plan_bytes(4u, 0xc1430f48u); // cmovae rax, rcx
        }
        plan_move(target_wide, X86_REG, locations.result);
        return;
    }
    // Integer and bool sources: extend to 64 bits by source signedness. A
    // 32-bit move zero-extends; movsxd rax, eax sign-extends.
    bool source_wide = scalar_uses_64bit_gpr(source);
    plan_move(source_wide, locations.b, X86_REG);
    if (!source_wide && scalar_is_signed_integer(source)) plan_bytes(3u, 0xc06348u);
    if (target_float)
    {
        if (scalar_is_unsigned_integer(source) && source_wide)
        {
            // u64 values >= 2^63 halve with a sticky low bit, convert and
            // double: test rax, rax; js +7; cvtsi2s? xmm15, rax; jmp +22;
            // mov rcx, rax; shr rcx, 1; and eax, 1; or rcx, rax;
            // cvtsi2s? xmm15, rcx; adds? xmm15, xmm15
            plan_bytes_word(1u, 0x48u, 0x0778c085u);
            plan_bytes_word(1u, to_float_prefix, 0xf82a0f4cu);
            plan_bytes(2u, 0x16ebu);
            plan_bytes(3u, 0xc18948u);
            plan_bytes(3u, 0xe9d148u);
            plan_bytes(3u, 0x01e083u);
            plan_bytes(3u, 0xc10948u);
            plan_bytes_word(1u, to_float_prefix, 0xf92a0f4cu);
            plan_bytes_word(1u, to_float_prefix, 0xff580f45u);
        }
        else plan_bytes_word(1u, to_float_prefix, 0xf82a0f4cu);
        plan_xmm(target_f64, false, 15u, locations.result);
        return;
    }
    plan_integer_width_normalize(target);
    plan_move(target_wide, X86_REG, locations.result);
}

void plan_float(X86PlanInput input)
{
    X86LirCore core = input.core;
    X86LirOperands operands = input.operands;
    X86LirLocations locations = input.locations;
    bool wide = x86_scalar_f64(operands.metadata);
    if (core.op == X86_LIR_OP_UNARY)
    {
        plan_value_move(true, wide, locations.b, X86_REG);
        if (wide) plan_bytes_word(1u, 0x48u, 0x3ff8ba0fu); // btc rax, 63
        else plan_bytes_word(1u, 0x35u, 0x80000000u); // xor eax, 0x80000000
        plan_value_move(true, wide, X86_REG, locations.result);
        return;
    }
    bool binary = core.op == X86_LIR_OP_BINARY;
    bool branch = core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE;
    uint left = branch ? locations.a : locations.b;
    uint right = branch ? locations.b : locations.c;
    uint compute;
    if (binary)
    {
        uint destination = x86_location_is_xmm(locations.result)
            ? x86_location_xmm(locations.result) : 15u;
        bool destination_is_right = x86_location_is_xmm(right) &&
            x86_location_xmm(right) == destination;
        bool destination_is_left = x86_location_is_xmm(left) &&
            x86_location_xmm(left) == destination;
        if (destination_is_right && !destination_is_left &&
            float_binary_commutative(operands.a))
        {
            uint swap = left;
            left = right;
            right = swap;
            destination_is_right = false;
        }
        compute = destination_is_right && !destination_is_left ? 15u : destination;
    }
    else compute = x86_location_is_xmm(left) ? x86_location_xmm(left) : 15u;
    plan_xmm(wide, true, compute, left);
    if (!x86_location_is_xmm(right) && x86_location_is_register(right))
        plan_xmm(wide, true, 14u, right);
    plan_op(X86_OP_FLOAT_ARITHMETIC | select(wide, 1u << 8u, 0u) |
        select(binary, 0u, 2u << 8u), operands.a, compute, right);
    if (binary)
    {
        plan_xmm(wide, false, compute, locations.result);
        return;
    }
    // UCOMISS/UCOMISD set ZF, PF, and CF for unordered operands. Combine
    // SETcc with parity so NaN is true only for !=, regardless of result use.
    uint predicate = branch ? core.local_ordinal : operands.a;
    uint setcc = predicate == 0u ? 0x94u : predicate == 1u ? 0x95u :
        predicate == 2u ? 0x92u : predicate == 3u ? 0x97u :
        predicate == 4u ? 0x96u : 0x93u;
    // setp/setnp ah; setcc al; or/and al, ah
    plan_bytes_word(4u, 0x0fc4000fu | (select(predicate == 1u, 0x9au, 0x9bu) << 8u),
        setcc | 0xe000c000u | (select(predicate == 1u, 0x08u, 0x20u) << 16u));
    if (branch) plan_jump(4u, 0x840fc084u, X86_RESOLVE_ROW, core.result_or_target); // test al,al; jz
    else
    {
        plan_bytes(3u, 0xc0b60fu); // movzx eax, al
        plan_move32(X86_REG, locations.result);
    }
}

// Returns the word count of a trailing memmove whose RDI/RSI pushes have been
// planned, or zero.
uint plan_specialized(X86PlanInput input)
{
    X86LirCore core = input.core;
    X86LirOperands operands = input.operands;
    X86LirLocations locations = input.locations;
    uint metadata = operands.metadata;
    uint op = core.op;
    if (op == X86_LIR_OP_UNARY && operands.a == X86_LIR_UNARY_CONVERT)
    {
        plan_convert(input);
        return 0u;
    }
    uint integer_type = metadata & 0xffu;
    bool is_float = x86_scalar_float(metadata);
    bool f64 = x86_scalar_f64(metadata);
    bool distinct_integer_width = scalar_is_wide_integer(integer_type) ||
        scalar_is_narrow_integer(integer_type);
    bool wide_integer = scalar_is_wide_integer(integer_type);
    if (op == X86_LIR_OP_IMM_I64)
    {
        // Only wide-integer and f64 immediates have a 64-bit body.
        if (!x86_is_specialized_scalar_instruction(core, operands)) return 0u;
        plan_bytes_words(2u, 0xb848u, operands.a, operands.b); // movabs rax, imm64
        plan_value_move(f64, true, X86_REG, locations.result);
        return 0u;
    }
    if (x86_is_specialized_float_instruction(core, operands))
    {
        plan_float(input);
        return 0u;
    }
    if ((op == X86_LIR_OP_BINARY && distinct_integer_width) ||
        (op == X86_LIR_OP_UNARY && distinct_integer_width && operands.a == X86_LIR_UNARY_NEG_I32))
    {
        bool binary = op == X86_LIR_OP_BINARY;
        bool shift = operands.a == X86_LIR_BINARY_SHL_I32 || operands.a == X86_LIR_BINARY_SHR_I32;
        bool is_signed = scalar_is_signed_integer(integer_type);
        plan_move(wide_integer, locations.b, X86_REG);
        if (!binary) plan_prefixed(wide_integer, 0x48u, 2u, 0xd8f7u); // neg
        else
        {
            plan_move(wide_integer && (!shift || (metadata & X86_LIR_METADATA_RHS_NARROW) == 0u),
                locations.c, X86_REG | 1u);
            if (operands.a == X86_LIR_BINARY_DIV_I32 || operands.a == X86_LIR_BINARY_REM_I32)
            {
                if (is_signed) plan_prefixed(wide_integer, 0x48u, 1u, 0x99u); // cdq/cqo
                else plan_bytes(2u, 0xd231u); // xor edx, edx
                plan_prefixed(wide_integer, 0x48u, 2u, 0xf7u | (select(is_signed, 0xf9u, 0xf1u) << 8u));
                if (operands.a == X86_LIR_BINARY_REM_I32)
                    plan_prefixed(wide_integer, 0x48u, 2u, 0xd089u);
            }
            else if (operands.a == X86_LIR_BINARY_MUL_I32)
                plan_prefixed(wide_integer, 0x48u, 3u, 0xc1af0fu);
            else if (shift)
                plan_prefixed(wide_integer, 0x48u, 2u, 0xd3u |
                    ((operands.a == X86_LIR_BINARY_SHL_I32 ? 0xe0u : is_signed ? 0xf8u : 0xe8u) << 8u));
            else plan_prefixed(wide_integer, 0x48u, 2u, 0xc800u |
                (operands.a == X86_LIR_BINARY_ADD_I32 ? 0x01u :
                 operands.a == X86_LIR_BINARY_SUB_I32 ? 0x29u :
                 operands.a == X86_LIR_BINARY_BIT_AND_I32 ? 0x21u :
                 operands.a == X86_LIR_BINARY_BIT_OR_I32 ? 0x09u : 0x31u));
        }
        plan_integer_width_normalize(integer_type);
        plan_move(wide_integer, X86_REG, locations.result);
        return 0u;
    }
    if (op == X86_LIR_OP_BINARY && integer_type == SCALAR_PTR)
    {
        plan_move64(locations.b, X86_REG);
        bool wide_offset = scalar_is_wide_integer(core.local_ordinal);
        plan_move(wide_offset, locations.c, X86_REG | 1u);
        if (!wide_offset && scalar_is_signed_integer(core.local_ordinal))
            plan_bytes(3u, 0xc96348u); // movsxd rcx, ecx
        plan_bytes(3u, 0xc80048u | (select(operands.a == X86_LIR_BINARY_SUB_I32, 0x29u, 0x01u) << 8u));
        plan_move64(X86_REG, locations.result);
        return 0u;
    }
    if ((op == X86_LIR_OP_COMPARE || op == X86_LIR_OP_COMPARE_BRANCH_FALSE) &&
        x86_is_specialized_integer_instruction(core, operands))
    {
        bool branch = op == X86_LIR_OP_COMPARE_BRANCH_FALSE;
        plan_move64(branch ? locations.a : locations.b, X86_REG);
        plan_move((metadata & X86_LIR_METADATA_RHS_NARROW) == 0u,
            branch ? locations.b : locations.c, X86_REG | 1u);
        plan_bytes(3u, 0xc83948u); // cmp rax, rcx
        if (branch)
            plan_jump(2u, 0x0fu | (((plan_integer_setcc_opcode(core.local_ordinal, integer_type)
                ^ 1u) - 0x10u) << 8u), X86_RESOLVE_ROW, core.result_or_target);
        else plan_op(X86_OP_BOOLEAN_RESULT,
            plan_integer_setcc_opcode(operands.a, integer_type), locations.result, 0u);
        return 0u;
    }
    // Explicit place and index bodies.
    if (op == X86_LIR_OP_INDEX_ADDRESS || op == X86_LIR_OP_INDEX_LOAD ||
        op == X86_LIR_OP_INDEX_STORE)
    {
        bool string = integer_type == SEMANTIC_LIR_TY_STRING;
        bool aggregate = (metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        bool packed = (metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u;
        // plan_index_address leaves a runtime view's byte stride in RCX.
        bool runtime_u8 = integer_type == SCALAR_U8 &&
            core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME;
        bool copy = op == X86_LIR_OP_INDEX_STORE &&
            (metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) != 0u;
        bool pair_store = op == X86_LIR_OP_INDEX_STORE && !copy &&
            (string || (metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u);
        uint words = op == X86_LIR_OP_INDEX_ADDRESS ? operands.c :
            op == X86_LIR_OP_INDEX_LOAD ? (string ? 2u : aggregate ? operands.c : 1u) :
            copy ? core.result_or_target :
            pair_store ? ((metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u ? NATIVE_SLICE_WORDS : 2u) : 1u;
        // An empty aggregate copy writes nothing; its safety guard still checks bounds.
        if (copy && words == 0u) return 0u;
        if (copy) plan_bytes(2u, 0x5657u); // push rdi; push rsi
        plan_index_address(input, words);
        if (op == X86_LIR_OP_INDEX_ADDRESS) plan_move64(X86_REG, locations.result);
        else if (op == X86_LIR_OP_INDEX_LOAD)
        {
            if (string)
            {
                // mov rdx, [rax]; mov ecx, [rax-8]
                plan_bytes_word(2u, 0x8b48u, 0xf8488b10u);
                plan_move64(X86_REG | 2u, locations.result);
                plan_move32(X86_REG | 1u, locations.result + 1u);
            }
            else
            {
                bool f32 = !aggregate && integer_type == X86_LIR_TY_FLOAT;
                bool packed_load = !aggregate && packed;
                // A u8 view's stride (RCX) is +1 over raw bytes and -8 over a
                // native array's words. A byte view loads one byte:
                // cmp rcx, 1; jne +5; movzx eax, byte [rax]; jmp +3
                if (!aggregate && runtime_u8)
                    plan_bytes_words(3u, 0xf98348u, 0x0f057501u, 0x03eb00b6u);
                if (!aggregate) plan_prefixed(!packed_load && !f32, 0x48u, 2u, 0x008bu);
                plan_value_move(is_float, is_float ? f64 : !packed_load, X86_REG, locations.result);
            }
        }
        else if (copy)
        {
            plan_move64(locations.c, X86_REG | 2u);
            return words;
        }
        else if (pair_store)
        {
            for (uint component = 0u; component < words; component++)
            {
                plan_move(component != 1u, locations.c + component, X86_REG | 2u);
                plan_bytes_word(3u, 0x908948u, x86_native_word_displacement(component));
            }
        }
        else
        {
            plan_value_move(is_float, is_float ? f64 : !packed, locations.c, X86_REG | 2u);
            // A byte view stores one byte, as the load above reads one:
            // cmp rcx, 1; jne +4; mov [rax], dl; jmp +3
            if (runtime_u8) plan_bytes_words(2u, 0x8348u, 0x047501f9u, 0x03eb1088u);
            plan_prefixed(!packed, 0x48u, 2u, 0x1089u); // mov [rax], edx/rdx
        }
        return 0u;
    }
    if (op == X86_LIR_OP_DECL_ADDRESS)
    {
        plan_lea64(0u, input.place_slot);
        plan_move64(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_FIELD_ADDRESS)
    {
        plan_move64(locations.a, X86_REG);
        plan_bytes_word(3u, 0x808d48u, 0u - operands.b * 8u);
        plan_move64(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_PLACE_LOAD || op == X86_LIR_OP_PLACE_STORE)
    {
        bool load = op == X86_LIR_OP_PLACE_LOAD;
        bool aggregate = (metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        uint descriptor = (metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u ? 3u :
            (metadata & X86_LIR_METADATA_STRING_PAIR) != 0u ? 2u : 0u;
        bool wide = scalar_uses_64bit_gpr(integer_type) || f64;
        if (load && aggregate)
        {
            // A value read owns its snapshot; the address operation owns the cell.
            plan_move64(locations.a, X86_REG | 2u);
            plan_lea64(0u, x86_location_payload(locations.result) + 1u);
            plan_move64(X86_REG, locations.result);
            if (operands.c == 0u) return 0u;
            plan_bytes(2u, 0x5657u);
            return operands.c;
        }
        plan_move64(locations.a, X86_REG);
        if (!load && (aggregate || (metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u))
        {
            plan_move64(locations.b, X86_REG | 2u);
            if ((metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
            {
                // Two micro-ops per packed word, indexed directly so long
                // copies do not replay the whole loop for every step.
                uint count = operands.c * 2u;
                uint step = x86_plan_target - x86_plan_index;
                if (x86_plan_target >= x86_plan_index && step < count)
                {
                    uint word = step >> 1u;
                    if ((step & 1u) == 0u)
                    {
                        x86_plan_head = X86_OP_BYTES | (2u << 8u) | X86_BYTES_ONE_WORD;
                        x86_plan_a = 0x8a8bu; // mov ecx, [rdx + word*4]
                        x86_plan_b = word * 4u;
                    }
                    else
                    {
                        x86_plan_head = X86_OP_BYTES | (3u << 8u) | X86_BYTES_ONE_WORD;
                        x86_plan_a = 0x888948u; // mov [rax - word*8], rcx
                        x86_plan_b = 0u - word * 8u;
                    }
                    x86_plan_c = 0u;
                }
                x86_plan_index += count;
                return 0u;
            }
            uint words = descriptor != 0u ? descriptor : operands.c;
            if (words == 0u) return 0u;
            plan_bytes(2u, 0x5657u);
            return words;
        }
        if (descriptor != 0u)
        {
            for (uint word = 0u; word < descriptor; word++)
            {
                if (load)
                {
                    // mov ecx/rcx, [rax - word*8]
                    plan_prefixed_word(word != 1u, 0x48u, 2u, 0x888bu, 0u - word * 8u);
                    plan_move(word != 1u, X86_REG | 1u, locations.result + word);
                }
                else
                {
                    plan_move(word != 1u, locations.b + word, X86_REG | 1u);
                    plan_bytes_word(3u, 0x888948u, 0u - word * 8u);
                }
            }
            return 0u;
        }
        if (load)
        {
            plan_prefixed(wide, 0x48u, 2u, 0x008bu); // mov eax/rax, [rax]
            plan_value_move(is_float, is_float ? f64 : wide, X86_REG, locations.result);
        }
        else
        {
            plan_value_move(is_float, is_float ? f64 : wide, locations.b, X86_REG | 1u);
            plan_prefixed(wide, 0x48u, 2u, 0x0889u); // mov [rax], ecx/rcx
        }
    }
    else if (op == X86_LIR_OP_PRINT_I32 && (operands.a == 1u || operands.a == 2u))
        // Scatter accepts only print (1) and assert (2) for this opcode.
        plan_jump(1u, 0xe8u, X86_RESOLVE_RUNTIME, operands.a == 2u
            ? X86_RUNTIME_ASSERT_OFFSET : X86_RUNTIME_PRINT_I32_OFFSET);
    else if (op == X86_LIR_OP_INTRINSIC_IDENTITY)
        // The preceding CALL_ARG rows placed the argument's words in RDI,
        // RSI and RDX. Operand a = 2 selects a view's stride in RDX.
        plan_move64(X86_REG | (operands.a == 2u ? 2u : 7u), locations.result);
    else if (op == X86_LIR_OP_CALL || op == X86_LIR_OP_CALL_SYMBOL)
    {
        // Strings occupy direct pointer/length value slots. The native pair
        // return is RAX/RDX, rather than an address of aggregate storage.
        bool local = op == X86_LIR_OP_CALL;
        if (local && input.callee_row == X86_PLAN_INVALID) return 0u;
        uint stack_bytes = local ? core.local_ordinal : x86_symbol_call_stack_bytes(core.local_ordinal);
        plan_op(X86_OP_BYTES | (1u << 8u) | X86_BYTES_ONE_WORD |
            select(local, (X86_RESOLVE_ROW << 13u) | X86_BYTES_REL, 0u),
            0xe8u, local ? input.callee_row : 0u, 0u);
        if (stack_bytes != 0u) plan_bytes_word(3u, 0xc48148u, stack_bytes);
        plan_move64(X86_REG, locations.result);
        plan_move32(X86_REG | 2u, locations.result + 1u);
    }
    else if (op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
    {
        if ((metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
        {
            // Preserve the native aggregate return ABI while unpacking an
            // ascending i32 array into its individual native result words.
            if (operands.c <= 2u)
            {
                if (operands.b == 0u)
                {
                    plan_move64(locations.a, X86_REG);
                    if (operands.c == 2u) plan_bytes(3u, 0x04508bu); // mov edx, [rax+4]
                    plan_bytes(2u, 0x008bu); // mov eax, [rax]
                }
            }
            else
            {
                plan_move64(locations.a, X86_REG);
                plan_load64(input.hidden_sret_slot, 10u);
                plan_base_i32_load(0x08u, x86_packed_i32_element_offset(operands.b));
                if (operands.b == 0u) plan_bytes(3u, 0x0a8949u); // mov [r10], rcx
                else plan_bytes_word(3u, 0x8a8949u, x86_native_word_displacement(operands.b));
            }
        }
        else if ((metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u)
        {
            plan_move(operands.b != NATIVE_SLICE_LENGTH, locations.a + operands.b, X86_REG | 1u);
            plan_load64(input.hidden_sret_slot, 10u);
            plan_bytes_word(3u, 0x8a8949u, x86_native_word_displacement(operands.b));
        }
        else if (operands.b == 0u)
        {
            plan_move32(locations.a + 1u, X86_REG | 2u);
            plan_move64(locations.a, X86_REG);
        }
    }
    else if (op == X86_LIR_OP_COMPARE)
    {
        plan_aggregate_word_compare(locations.b, locations.c);
        // setcc al; movzx eax, al
        plan_bytes_word(2u, 0x0fu | (plan_setcc_opcode(operands.a) << 8u), 0xc0b60fc0u);
        plan_move32(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        plan_aggregate_word_compare(locations.a, locations.b);
        plan_jump(2u, 0x0fu | (((plan_setcc_opcode(core.local_ordinal) ^ 1u) - 0x10u) << 8u),
            X86_RESOLVE_ROW, core.result_or_target);
    }
    else if (op == X86_LIR_OP_SELECT_STORE)
    {
        uint destination = input.decl_target;
        bool register_destination = x86_location_is_register(destination);
        uint selected = register_destination ? x86_location_payload(destination) : 2u;
        plan_move32(locations.result, register_destination ? destination : X86_REG | 2u);
        plan_aggregate_word_compare(locations.a, locations.b);
        plan_move32(locations.c, X86_REG);
        plan_prefixed(selected >= 8u, 0x44u, 3u, 0x0fu |
            ((plan_setcc_opcode(core.local_ordinal) - 0x50u) << 8u) |
            ((0xc0u | ((selected & 7u) << 3u)) << 16u));
        if (!register_destination) plan_move32(X86_REG | 2u, destination);
    }
    else if (op == X86_LIR_OP_CALL_ARG)
    {
        bool stack_argument = operands.b >= 6u;
        if (stack_argument && core.local_ordinal != 0u) plan_bytes(4u, 0x08ec8348u);
        uint destination = X86_REG | (stack_argument ? 0u : x86_abi_argument_register(operands.b));
        // FIELD_LOAD yields the address of the in-struct slice pair. Load its
        // selected word before placing it in the ABI argument slot.
        plan_move64(locations.a, X86_REG);
        plan_bytes_word(3u, 0x808b48u, 0u - operands.c * 8u);
        plan_move(operands.c != NATIVE_SLICE_LENGTH, X86_REG, destination);
        if (stack_argument) plan_bytes(1u, 0x50u);
    }
    else if (op == X86_LIR_OP_FIELD_STORE)
    {
        plan_move64(locations.a, X86_REG);
        if ((metadata & (X86_LIR_METADATA_STRING_PAIR | X86_LIR_METADATA_ARRAY_PAIR)) != 0u)
            // Direct descriptors occupy adjacent value slots; both words
            // belong to the store.
            plan_move(core.local_ordinal != NATIVE_SLICE_LENGTH,
                locations.c + core.local_ordinal, X86_REG | 1u);
        else
        {
            plan_move64(locations.c, X86_REG | 1u);
            // Packed local arrays ascend in four-byte elements; inline fields
            // descend in native words.
            if ((metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
                plan_base_i32_load(0x09u, core.local_ordinal * 4u);
            else if (core.local_ordinal == 0u) plan_bytes(3u, 0x098b48u);
            else plan_bytes_word(3u, 0x898b48u, 0u - core.local_ordinal * 8u);
        }
        plan_bytes_word(3u, 0x888948u, x86_native_word_displacement(operands.b));
    }
    else if (op == X86_LIR_OP_STORE_LOCAL)
    {
        uint destination = input.decl_a;
        if ((metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u)
        {
            bool indirect = (metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u;
            if (indirect) plan_move64(locations.b, X86_REG);
            for (uint component = 0u; component < NATIVE_SLICE_WORDS; component++)
            {
                if (indirect)
                    plan_bytes_word(3u, 0x888b48u, x86_native_word_displacement(component));
                else plan_move(component != NATIVE_SLICE_LENGTH, locations.b + component, X86_REG | 1u);
                plan_move64(X86_REG | 1u, destination + component);
            }
        }
        else
        {
            plan_lea64(0u, x86_location_payload(locations.result) + operands.c);
            plan_move64(X86_REG, destination);
        }
    }
    else if (op == X86_LIR_OP_AGGREGATE_ADDR)
    {
        plan_lea64(0u, x86_location_payload(locations.result) + operands.c);
        plan_move64(X86_REG, locations.result);
    }
    else if (op == X86_LIR_OP_AGGREGATE_INIT)
    {
        if ((metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            // Packed i32 source, native word destination (e.g. an inline array
            // field). The ABI's word order is preserved by locations.c.
            plan_move64(locations.a, X86_REG);
            plan_bytes_word(2u, 0x808bu, x86_packed_i32_element_offset(operands.b));
            plan_move64(X86_REG, locations.c);
            return 0u;
        }
        if ((metadata & X86_LIR_METADATA_IMMEDIATE) != 0u) plan_bytes_word(1u, 0xb8u, operands.a);
        else plan_move32(locations.a, X86_REG);
        uint allocation_slot = x86_location_payload(locations.result) - core.local_ordinal;
        plan_store_packed_i32(0u, allocation_slot + operands.c, core.local_ordinal - 1u);
    }
    else if (op == X86_LIR_OP_AGGREGATE_COPY_WORD)
    {
        plan_move64(locations.a, X86_REG);
        plan_base_i32_load(0x08u, (metadata & X86_LIR_METADATA_AGGREGATE) != 0u
            ? x86_native_word_displacement(operands.b) : x86_packed_i32_element_offset(operands.b));
        uint allocation_slot = x86_location_payload(locations.result) - operands.b - 1u;
        plan_store_packed_i32(1u, allocation_slot + operands.c, operands.b);
    }
    else if (op == X86_LIR_OP_INTRINSIC_SLICE_FROM_RAW_PARTS)
    {
        // The preceding CALL_ARG rows placed data in RDI and length in RSI.
        // Normalize the signed-i32 length to an unsigned machine word before
        // publishing the native pointer-and-length pair.
        uint storage_slot = x86_location_payload(locations.result) + 1u;
        plan_store64(7u, storage_slot);
        plan_bytes(2u, 0xf689u); // mov esi, esi
        plan_store64(6u, storage_slot + 1u);
        plan_bytes_word(3u, 0xc0c748u, operands.a);
        plan_store64(0u, storage_slot + NATIVE_SLICE_STRIDE);
        plan_lea64(0u, storage_slot);
        plan_move64(X86_REG, locations.result);
    }
    return 0u;
}

X86PlanOp x86_plan(X86PlanInput input, uint step)
{
    x86_plan_target = step;
    x86_plan_index = 0u;
    x86_plan_head = X86_OP_END;
    x86_plan_a = 0u;
    x86_plan_b = 0u;
    x86_plan_c = 0u;
    if (!input.skip_body)
    {
        if (input.specialized)
        {
            uint memmove_words = plan_specialized(input);
            if (memmove_words != 0u) plan_memmove_tail(memmove_words);
        }
        else plan_ordinary(input);
    }
    if (input.footer) plan_footer(input);
    X86PlanOp op;
    op.head = x86_plan_head;
    op.a = x86_plan_a;
    op.b = x86_plan_b;
    op.c = x86_plan_c;
    return op;
}
