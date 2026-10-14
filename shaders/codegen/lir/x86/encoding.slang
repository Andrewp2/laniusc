// One x86-64 encoder for every target instruction body.
//
// The instruction plan (instruction_plan.slang) describes a row's body as a
// sequence of micro-ops. This module turns one micro-op into at most sixteen
// machine-code bytes. Byte counting and emission both run the same plan and
// this encoder, so counted lengths and emitted bytes cannot disagree, and each
// encoding routine exists once instead of once per emitter call site.
import codegen.lowering_ir;
import codegen.lir.x86.storage_layout;
import codegen.lir.x86.location_common;

// Micro-op head: kind in bits 0-7, kind-specific fields above.
static const uint X86_OP_END = 0u;
// Raw bytes. Bits 8-10: count of leading bytes taken from `a` (0..4);
// bits 11-12: number of 32-bit words that follow (`b`, then `c`);
// bits 13-15: how emission resolves word `b` (X86_RESOLVE_*); bit 16: `b`
// becomes rel32 relative to the end of this micro-op; bit 17: a prefix byte
// (bits 24-31) precedes everything.
static const uint X86_OP_BYTES = 1u;
// RBP-relative load/store/LEA. Bits 8-15 opcode, bit 16 REX.W, bit 17 `b` is
// a byte displacement rather than a native-word slot. `a` register.
static const uint X86_OP_STACK = 2u;
// Location move `a` -> `b`. Bit 8 64-bit, bit 9 float locations may be XMM.
static const uint X86_OP_MOVE = 3u;
// Scalar float transfer between XMM `a` and location `b`. Bit 8 f64, bit 9
// direction is location -> XMM.
static const uint X86_OP_XMM = 4u;
static const uint X86_OP_IMM32_TO_LOCATION = 5u;   // value a, destination b
static const uint X86_OP_BINARY32 = 6u;            // operation a, right b, destination c
static const uint X86_OP_LEA_ADD32 = 7u;           // left a, right b, destination c
static const uint X86_OP_LEA_SCALED32 = 8u;        // source a, destination b, scale c
static const uint X86_OP_IMUL_IMMEDIATE32 = 9u;    // immediate a, source b, destination c
static const uint X86_OP_LEA_DISPLACED32 = 10u;    // displacement a, source b, destination c
static const uint X86_OP_INC_DEC32 = 11u;          // destination a, decrement b
static const uint X86_OP_COMPARE_LOCATIONS32 = 12u; // left a, right b
static const uint X86_OP_TEST_LOCATION32 = 13u;    // location a
static const uint X86_OP_COMPARE_IMMEDIATE32 = 14u; // immediate a, source b
static const uint X86_OP_BOOLEAN_RESULT = 15u;     // setcc opcode a, destination b
// UCOMIS/ADDS-family instruction. Bit 8 f64, bit 9 compare; operation a,
// destination XMM b, right location c (a GPR right is already in XMM14).
static const uint X86_OP_FLOAT_ARITHMETIC = 16u;
// ALU r32, imm with ModRM extension a, register b, immediate c.
static const uint X86_OP_GROUP1_IMMEDIATE32 = 17u;

static const uint X86_RESOLVE_NONE = 0u;
static const uint X86_RESOLVE_ROW = 1u;          // body offset of target row b
static const uint X86_RESOLVE_RUNTIME = 2u;      // runtime offset + b
static const uint X86_RESOLVE_STRING_ADDR = 3u;  // address of string b
static const uint X86_RESOLVE_STRING_LEN = 4u;   // decoded length of string b

struct X86PlanOp
{
    uint head;
    uint a;
    uint b;
    uint c;
};

struct X86Code
{
    uint w0;
    uint w1;
    uint w2;
    uint w3;
    uint length;
};

static uint x86_code_w0;
static uint x86_code_w1;
static uint x86_code_w2;
static uint x86_code_w3;
static uint x86_code_length;

uint x86_op_kind(uint head) { return head & 0xffu; }

uint x86_bytes_op_length(uint head)
{
    return ((head >> 8u) & 7u) + ((head >> 11u) & 3u) * 4u + ((head >> 17u) & 1u);
}

void x86_put(uint value)
{
    uint word = x86_code_length >> 2u;
    uint shifted = (value & 0xffu) << ((x86_code_length & 3u) * 8u);
    x86_code_w0 |= select(word == 0u, shifted, 0u);
    x86_code_w1 |= select(word == 1u, shifted, 0u);
    x86_code_w2 |= select(word == 2u, shifted, 0u);
    x86_code_w3 |= select(word == 3u, shifted, 0u);
    x86_code_length += 1u;
}

void x86_put_u32(uint value)
{
    for (uint i = 0u; i < 4u; i += 1u) x86_put(value >> (i * 8u));
}

void x86_put_if(bool present, uint value)
{
    if (present) x86_put(value);
}

// RBP-relative ModRM with an 8- or 32-bit displacement.
void x86_put_rbp_modrm(uint reg, uint byte_displacement, bool narrow)
{
    x86_put(select(narrow, 0x40u, 0x80u) | ((reg & 7u) << 3u) | 5u);
    if (narrow) x86_put(byte_displacement);
    else x86_put_u32(byte_displacement);
}

void x86_put_stack_modrm(uint reg, uint slot)
{
    x86_put_rbp_modrm(reg, x86_native_word_displacement(slot + 1u),
        x86_stack_displacement_bytes(slot) == 1u);
}

// load32 8B, store32 89 (REX 44 for high registers); with REX.W also LEA 8D.
void x86_put_stack(uint opcode, bool wide, uint reg, uint slot)
{
    if (wide) x86_put(0x48u | select(reg >= 8u, 4u, 0u));
    else x86_put_if(reg >= 8u, 0x44u);
    x86_put(opcode);
    x86_put_stack_modrm(reg, slot);
}

void x86_put_register_move(bool wide, uint source, uint destination)
{
    if (source == destination) return;
    uint rex = select(wide, 0x48u, 0x40u) | select(source >= 8u, 4u, 0u) |
        select(destination >= 8u, 1u, 0u);
    x86_put_if(rex != 0x40u, rex);
    x86_put(0x89u);
    x86_put(0xc0u | ((source & 7u) << 3u) | (destination & 7u));
}

void x86_put_move(bool wide, uint source, uint destination)
{
    if (source == destination && source != X86_LOCATION_INVALID) return;
    bool source_register = x86_location_is_register(source);
    bool destination_register = x86_location_is_register(destination);
    uint source_payload = x86_location_payload(source);
    uint destination_payload = x86_location_payload(destination);
    if (source_register && destination_register)
    {
        x86_put_register_move(wide, source_payload, destination_payload);
        return;
    }
    // Memory-to-memory moves go through RAX.
    uint load_register = destination_register ? destination_payload : 0u;
    if (!source_register) x86_put_stack(0x8bu, wide, load_register, source_payload);
    if (!destination_register)
        x86_put_stack(0x89u, wide, source_register ? source_payload : 0u,
            destination_payload);
}

void x86_put_xmm(bool wide, bool to_xmm, uint xmm, uint location)
{
    uint scalar_prefix = select(wide, 0xf2u, 0xf3u);
    if (x86_location_is_xmm(location))
    {
        uint other = x86_location_xmm(location);
        if (other == xmm) return;
        uint reg = to_xmm ? xmm : other;
        uint rm = to_xmm ? other : xmm;
        x86_put(scalar_prefix);
        uint rex = 0x40u | select(reg >= 8u, 4u, 0u) | select(rm >= 8u, 1u, 0u);
        x86_put_if(rex != 0x40u, rex);
        x86_put(0x0fu); x86_put(0x10u);
        x86_put(0xc0u | ((reg & 7u) << 3u) | (rm & 7u));
        return;
    }
    if (x86_location_is_register(location))
    {
        uint gpr = x86_location_payload(location);
        x86_put(0x66u);
        uint rex = select(wide, 0x48u, 0x40u) | select(xmm >= 8u, 4u, 0u) |
            select(gpr >= 8u, 1u, 0u);
        x86_put_if(rex != 0x40u, rex);
        x86_put(0x0fu); x86_put(to_xmm ? 0x6eu : 0x7eu);
        x86_put(0xc0u | ((xmm & 7u) << 3u) | (gpr & 7u));
        return;
    }
    x86_put(scalar_prefix);
    x86_put_if(xmm >= 8u, 0x44u);
    x86_put(0x0fu); x86_put(to_xmm ? 0x10u : 0x11u);
    x86_put_stack_modrm(xmm, x86_location_payload(location));
}

void x86_put_bytes(uint head, uint a, uint b, uint c)
{
    if (((head >> 17u) & 1u) != 0u) x86_put(head >> 24u);
    uint count = (head >> 8u) & 7u;
    for (uint i = 0u; i < count; i += 1u) x86_put(a >> (i * 8u));
    uint words = (head >> 11u) & 3u;
    for (uint word = 0u; word < words; word += 1u)
        x86_put_u32(word == 0u ? b : c);
}

void x86_put_imm32_to_location(uint value, uint destination)
{
    if (x86_location_is_register(destination))
    {
        uint gpr = x86_location_payload(destination);
        if (value == 0u)
        {
            x86_put_if(gpr >= 8u, 0x45u);
            x86_put(0x31u);
            x86_put(0xc0u | ((gpr & 7u) << 3u) | (gpr & 7u));
            return;
        }
        x86_put_if(gpr >= 8u, 0x41u);
        x86_put(0xb8u + (gpr & 7u));
        x86_put_u32(value);
        return;
    }
    if (value == 0u) { x86_put(0x31u); x86_put(0xc0u); }
    else { x86_put(0xb8u); x86_put_u32(value); }
    x86_put_stack(0x89u, false, 0u, x86_location_payload(destination));
}

void x86_put_binary32(uint operation, uint right, uint destination)
{
    uint destination_gpr = x86_location_payload(destination);
    bool right_register = x86_location_is_register(right);
    uint right_payload = x86_location_payload(right);
    uint rex = 0x40u | select(destination_gpr >= 8u, 4u, 0u) |
        select(right_register && right_payload >= 8u, 1u, 0u);
    x86_put_if(rex != 0x40u, rex);
    if (operation == X86_LIR_BINARY_MUL_I32) { x86_put(0x0fu); x86_put(0xafu); }
    else x86_put(
        operation == X86_LIR_BINARY_ADD_I32 ? 0x03u :
        operation == X86_LIR_BINARY_SUB_I32 ? 0x2bu :
        operation == X86_LIR_BINARY_BIT_AND_I32 ||
            operation == X86_LIR_BINARY_AND_BOOL ? 0x23u :
        operation == X86_LIR_BINARY_BIT_OR_I32 ||
            operation == X86_LIR_BINARY_OR_BOOL ? 0x0bu : 0x33u);
    if (right_register)
        x86_put(0xc0u | ((destination_gpr & 7u) << 3u) | (right_payload & 7u));
    else x86_put_stack_modrm(destination_gpr, right_payload);
}

// LEA r32 with a SIB byte: base + index * (1 << scale), RBP/R13 bases take
// an explicit zero displacement.
void x86_put_lea_sib(uint destination_gpr, uint rex, uint sib, uint base)
{
    x86_put_if(rex != 0x40u, rex);
    x86_put(0x8du);
    bool displaced_base = (base & 7u) == 5u;
    x86_put(select(displaced_base, 0x40u, 0u) | ((destination_gpr & 7u) << 3u) | 4u);
    x86_put(sib);
    x86_put_if(displaced_base, 0u);
}

void x86_put_lea_add32(uint left, uint right, uint destination)
{
    uint base = x86_location_payload(left);
    uint index = x86_location_payload(right);
    if ((index & 7u) == 4u)
    {
        uint swap = base;
        base = index;
        index = swap;
    }
    uint destination_gpr = x86_location_payload(destination);
    uint rex = 0x40u | select(destination_gpr >= 8u, 4u, 0u) |
        select(index >= 8u, 2u, 0u) | select(base >= 8u, 1u, 0u);
    x86_put_lea_sib(destination_gpr, rex, ((index & 7u) << 3u) | (base & 7u), base);
}

void x86_put_lea_scaled32(uint source, uint destination, uint scale)
{
    uint source_gpr = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    uint rex = 0x40u | select(destination_gpr >= 8u, 4u, 0u) |
        select(source_gpr >= 8u, 3u, 0u);
    x86_put_lea_sib(destination_gpr, rex,
        (scale << 6u) | ((source_gpr & 7u) << 3u) | (source_gpr & 7u), source_gpr);
}

void x86_put_imul_immediate32(uint immediate, uint source, uint destination)
{
    uint source_payload = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    bool source_register = x86_location_is_register(source);
    uint rex = 0x40u | select(destination_gpr >= 8u, 4u, 0u) |
        select(source_register && source_payload >= 8u, 1u, 0u);
    x86_put_if(rex != 0x40u, rex);
    bool narrow = x86_immediate_fits_i8(immediate);
    x86_put(select(narrow, 0x6bu, 0x69u));
    if (source_register)
        x86_put(0xc0u | ((destination_gpr & 7u) << 3u) | (source_payload & 7u));
    else x86_put_stack_modrm(destination_gpr, source_payload);
    if (narrow) x86_put(immediate);
    else x86_put_u32(immediate);
}

void x86_put_lea_displaced32(uint displacement, uint source, uint destination)
{
    uint source_gpr = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    uint rex = 0x40u | select(destination_gpr >= 8u, 4u, 0u) |
        select(source_gpr >= 8u, 1u, 0u);
    x86_put_if(rex != 0x40u, rex);
    x86_put(0x8du);
    bool narrow = x86_immediate_fits_i8(displacement);
    bool sib = (source_gpr & 7u) == 4u;
    x86_put(select(narrow, 0x40u, 0x80u) | ((destination_gpr & 7u) << 3u) |
        select(sib, 4u, source_gpr & 7u));
    x86_put_if(sib, 0x24u);
    if (narrow) x86_put(displacement);
    else x86_put_u32(displacement);
}

void x86_put_compare_locations32(uint left, uint right)
{
    bool left_register = x86_location_is_register(left);
    bool right_register = x86_location_is_register(right);
    uint left_payload = x86_location_payload(left);
    uint right_payload = x86_location_payload(right);
    if (!left_register && !right_register)
    {
        x86_put_stack(0x8bu, false, 0u, left_payload);
        x86_put_stack(0x8bu, false, 1u, right_payload);
        x86_put(0x39u); x86_put(0xc8u);
        return;
    }
    if (left_register && right_register)
    {
        // cmp left, right: opcode 39 encodes left as r/m and right as reg.
        uint rex = 0x40u | select(right_payload >= 8u, 4u, 0u) |
            select(left_payload >= 8u, 1u, 0u);
        x86_put_if(rex != 0x40u, rex);
        x86_put(0x39u);
        x86_put(0xc0u | ((right_payload & 7u) << 3u) | (left_payload & 7u));
        return;
    }
    // With one stack operand, opcode 39 handles stack-left/register-right;
    // opcode 3B preserves the operand order for register-left/stack-right.
    uint reg = left_register ? left_payload : right_payload;
    uint rm = left_register ? right_payload : left_payload;
    x86_put_if(reg >= 8u, 0x44u);
    x86_put(select(left_register, 0x3bu, 0x39u));
    x86_put_stack_modrm(reg, rm);
}

// test r32, r32 (REX 45 for high registers).
void x86_put_test_self(uint reg)
{
    x86_put_if(reg >= 8u, 0x45u);
    x86_put(0x85u);
    x86_put(0xc0u | ((reg & 7u) << 3u) | (reg & 7u));
}

void x86_put_compare_immediate32(uint immediate, uint source_location)
{
    bool source_register = x86_location_is_register(source_location);
    uint source = x86_location_payload(source_location);
    if (immediate == 0u && source_register)
    {
        x86_put_test_self(source);
        return;
    }
    bool narrow = x86_immediate_fits_i8(immediate);
    x86_put_if(source_register && source >= 8u, 0x41u);
    x86_put(select(narrow, 0x83u, 0x81u));
    if (source_register) x86_put(0xf8u | (source & 7u));
    else x86_put_stack_modrm(7u, source);
    if (narrow) x86_put(immediate);
    else x86_put_u32(immediate);
}

void x86_put_boolean_result(uint opcode, uint location)
{
    if (x86_location_is_register(location))
    {
        uint destination = x86_location_payload(location);
        x86_put_if(destination >= 4u, select(destination >= 8u, 0x41u, 0x40u));
        x86_put(0x0fu); x86_put(opcode);
        x86_put(0xc0u | (destination & 7u));
        x86_put_if(destination >= 4u, select(destination >= 8u, 0x45u, 0x40u));
        x86_put(0x0fu); x86_put(0xb6u);
        x86_put(0xc0u | ((destination & 7u) << 3u) | (destination & 7u));
        return;
    }
    x86_put(0x0fu); x86_put(opcode); x86_put(0xc0u);
    x86_put(0x0fu); x86_put(0xb6u); x86_put(0xc0u);
    x86_put_stack(0x89u, false, 0u, x86_location_payload(location));
}

void x86_put_float_arithmetic(bool wide, bool compare, uint operation,
                              uint destination, uint right)
{
    bool direct = x86_location_is_xmm(right) || x86_location_is_register(right);
    uint right_xmm = x86_location_is_xmm(right) ? x86_location_xmm(right) : 14u;
    if (compare) x86_put_if(wide, 0x66u); // UCOMISD; UCOMISS has no prefix.
    else x86_put(select(wide, 0xf2u, 0xf3u));
    uint rex = 0x40u | select(destination >= 8u, 4u, 0u) |
        select(direct && right_xmm >= 8u, 1u, 0u);
    x86_put_if(rex != 0x40u, rex);
    x86_put(0x0fu);
    x86_put(compare ? 0x2eu :
        operation == X86_LIR_BINARY_ADD_FLOAT ? 0x58u :
        operation == X86_LIR_BINARY_SUB_FLOAT ? 0x5cu :
        operation == X86_LIR_BINARY_MUL_FLOAT ? 0x59u : 0x5eu);
    if (direct) x86_put(0xc0u | ((destination & 7u) << 3u) | (right_xmm & 7u));
    else x86_put_stack_modrm(destination, x86_location_payload(right));
}

X86Code x86_encode(X86PlanOp op)
{
    x86_code_w0 = 0u;
    x86_code_w1 = 0u;
    x86_code_w2 = 0u;
    x86_code_w3 = 0u;
    x86_code_length = 0u;
    uint kind = x86_op_kind(op.head);
    bool bit8 = ((op.head >> 8u) & 1u) != 0u;
    bool bit9 = ((op.head >> 9u) & 1u) != 0u;
    if (kind == X86_OP_MOVE && bit9 &&
        !(op.a == op.b && op.a != X86_LOCATION_INVALID))
    {
        // Float values may live in XMM registers; GPR and stack homes use
        // the ordinary integer move below.
        if (x86_location_is_xmm(op.b))
        {
            // Location -> XMM: bit 9 already selects that direction.
            uint destination = op.b;
            kind = X86_OP_XMM;
            op.b = op.a;
            op.a = x86_location_xmm(destination);
        }
        else if (x86_location_is_xmm(op.a))
        {
            kind = X86_OP_XMM;
            bit9 = false;
            op.a = x86_location_xmm(op.a);
        }
    }
    if (kind == X86_OP_BYTES) x86_put_bytes(op.head, op.a, op.b, op.c);
    else if (kind == X86_OP_STACK)
    {
        uint opcode = (op.head >> 8u) & 0xffu;
        bool wide = ((op.head >> 16u) & 1u) != 0u;
        if (((op.head >> 17u) & 1u) != 0u)
        {
            x86_put_if(op.a >= 8u, 0x44u);
            x86_put(opcode);
            x86_put_rbp_modrm(op.a, op.b, x86_signed_displacement_bytes(op.b) == 1u);
        }
        else x86_put_stack(opcode, wide, op.a, op.b);
    }
    else if (kind == X86_OP_MOVE) x86_put_move(bit8, op.a, op.b);
    else if (kind == X86_OP_XMM) x86_put_xmm(bit8, bit9, op.a, op.b);
    else if (kind == X86_OP_IMM32_TO_LOCATION) x86_put_imm32_to_location(op.a, op.b);
    else if (kind == X86_OP_BINARY32) x86_put_binary32(op.a, op.b, op.c);
    else if (kind == X86_OP_LEA_ADD32) x86_put_lea_add32(op.a, op.b, op.c);
    else if (kind == X86_OP_LEA_SCALED32) x86_put_lea_scaled32(op.a, op.b, op.c);
    else if (kind == X86_OP_IMUL_IMMEDIATE32) x86_put_imul_immediate32(op.a, op.b, op.c);
    else if (kind == X86_OP_LEA_DISPLACED32) x86_put_lea_displaced32(op.a, op.b, op.c);
    else if (kind == X86_OP_INC_DEC32)
    {
        uint destination_gpr = x86_location_payload(op.a);
        x86_put_if(destination_gpr >= 8u, 0x41u);
        x86_put(0xffu);
        x86_put(select(op.b != 0u, 0xc8u, 0xc0u) | (destination_gpr & 7u));
    }
    else if (kind == X86_OP_COMPARE_LOCATIONS32) x86_put_compare_locations32(op.a, op.b);
    else if (kind == X86_OP_TEST_LOCATION32)
    {
        if (!x86_location_is_register(op.a))
        {
            x86_put_stack(0x8bu, false, 0u, x86_location_payload(op.a));
            x86_put(0x85u); x86_put(0xc0u);
        }
        else x86_put_test_self(x86_location_payload(op.a));
    }
    else if (kind == X86_OP_COMPARE_IMMEDIATE32) x86_put_compare_immediate32(op.a, op.b);
    else if (kind == X86_OP_BOOLEAN_RESULT) x86_put_boolean_result(op.a, op.b);
    else if (kind == X86_OP_FLOAT_ARITHMETIC)
        x86_put_float_arithmetic(bit8, bit9, op.a, op.b, op.c);
    else if (kind == X86_OP_GROUP1_IMMEDIATE32)
    {
        bool narrow = x86_immediate_fits_i8(op.c);
        x86_put_if(op.b >= 8u, 0x41u);
        x86_put(select(narrow, 0x83u, 0x81u));
        x86_put(0xc0u | (op.a << 3u) | (op.b & 7u));
        if (narrow) x86_put(op.c);
        else x86_put_u32(op.c);
    }
    X86Code code;
    code.w0 = x86_code_w0;
    code.w1 = x86_code_w1;
    code.w2 = x86_code_w2;
    code.w3 = x86_code_w3;
    code.length = x86_code_length;
    return code;
}

uint x86_code_byte(X86Code code, uint index)
{
    uint word = index < 4u ? code.w0 : index < 8u ? code.w1 :
        index < 12u ? code.w2 : code.w3;
    return (word >> ((index & 3u) * 8u)) & 0xffu;
}
