// Direct x86_64 instruction encoder.
//
// This pass consumes instruction records plus GPU-computed byte offsets and
// writes packed `.text` words. ELF construction consumes these final text bytes
// without knowing instruction template details.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_inst_kind;
StructuredBuffer<uint> x86_inst_arg0;
StructuredBuffer<uint> x86_inst_arg1;
StructuredBuffer<uint> x86_inst_arg2;
StructuredBuffer<uint> x86_inst_size;
StructuredBuffer<uint> x86_inst_byte_offset;
StructuredBuffer<uint> x86_text_len;
StructuredBuffer<uint> text_status;

RWStructuredBuffer<uint> x86_text_words;
RWStructuredBuffer<uint> encode_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_TEXT_OK = 1u;
static const uint X86_ENCODE_OK = 1u;
static const uint X86_INST_MOV_EAX_IMM32 = 1u;
static const uint X86_INST_MOV_EDI_IMM32 = 2u;
static const uint X86_INST_SYSCALL = 3u;
static const uint X86_INST_ADD_EAX_IMM32 = 4u;
static const uint X86_INST_SUB_EAX_IMM32 = 5u;
static const uint X86_INST_IMUL_EAX_EAX_IMM32 = 6u;
static const uint X86_INST_MOV_EDI_EAX = 7u;
static const uint X86_INST_CMP_EAX_IMM32 = 8u;
static const uint X86_INST_JCC_FALSE_REL32 = 9u;
static const uint X86_INST_JMP_REL32 = 10u;
static const uint X86_INST_SETCC_AL = 11u;
static const uint X86_INST_MOVZX_EDI_AL = 12u;
static const uint X86_INST_AND_EAX_IMM32 = 13u;
static const uint X86_INST_OR_EAX_IMM32 = 14u;
static const uint X86_INST_CALL_REL32 = 15u;
static const uint X86_INST_RET = 16u;
static const uint X86_INST_MOV_EAX_EDI = 17u;
static const uint X86_INST_MOV_ESI_IMM32 = 18u;
static const uint X86_INST_ADD_EAX_ESI = 19u;
static const uint X86_INST_SUB_EAX_ESI = 20u;
static const uint X86_INST_IMUL_EAX_ESI = 21u;
static const uint X86_INST_AND_EAX_ESI = 22u;
static const uint X86_INST_OR_EAX_ESI = 23u;
static const uint X86_INST_MOV_ESI_EAX = 24u;
static const uint X86_INST_MOV_EAX_ESI = 25u;
static const uint X86_INST_MOV_EAX_EDX = 26u;
static const uint X86_INST_MOV_EDX_IMM32 = 27u;
static const uint X86_INST_CMP_EAX_ESI = 28u;
static const uint X86_INST_NEG_EAX = 29u;
static const uint X86_INST_MOVZX_EAX_AL = 30u;
static const uint X86_INST_CMP_EAX_EDX = 31u;
static const uint X86_INST_CDQ = 32u;
static const uint X86_INST_MOV_ECX_IMM32 = 33u;
static const uint X86_INST_IDIV_ECX = 34u;
static const uint X86_INST_MOV_EDI_EDX = 35u;
static const uint X86_INST_MOV_ECX_EAX = 36u;
static const uint X86_INST_AND_EAX_ECX = 37u;
static const uint X86_INST_OR_EAX_ECX = 38u;
static const uint X86_INST_XOR_EAX_IMM32 = 39u;
static const uint X86_INST_SHL_EAX_IMM8 = 40u;
static const uint X86_INST_SAR_EAX_IMM8 = 41u;
static const uint X86_INST_XOR_EAX_ESI = 42u;
static const uint X86_INST_MOV_ESI_EDI = 43u;
static const uint X86_INST_MOV_EDX_EDI = 44u;
static const uint X86_INST_MOV_EDI_ESI = 45u;
static const uint X86_INST_MOV_EDX_ESI = 46u;
static const uint X86_INST_MOV_ESI_EDX = 47u;
static const uint X86_INST_DATA_I32_NL = 48u;
static const uint X86_INST_MOV_ESI_TEXT_ROW_ADDR = 49u;
static const uint X86_INST_V_MOV_R32_IMM32 = 50u;
static const uint X86_INST_V_MOV_R32_R32 = 51u;
static const uint X86_INST_V_UNARY_R32 = 52u;
static const uint X86_INST_V_BINARY_R32_R32 = 53u;
static const uint X86_INST_V_COMPARE_R32_R32 = 54u;
static const uint X86_INST_V_RETURN_R32 = 55u;
static const uint X86_INST_V_BRANCH_ZERO = 56u;
static const uint X86_INST_V_JMP = 57u;
static const uint X86_INST_V_PARAM_R32 = 58u;
static const uint X86_INST_V_CALL_DIRECT = 59u;
static const uint X86_INST_V_RETURN_FUNC_R32 = 60u;
static const uint X86_INST_V_PRINT_I32 = 61u;
static const uint X86_CMP_LT = 1u;
static const uint X86_CMP_GT = 2u;
static const uint X86_CMP_LE = 3u;
static const uint X86_CMP_GE = 4u;
static const uint X86_CMP_EQ = 5u;
static const uint X86_CMP_NE = 6u;
static const uint X86_CMP_UNSIGNED_FLAG = 0x80u;
static const uint X86_TEXT_VADDR = 0x400078u;
static const uint X86_OP_NEG_I32 = 1u;
static const uint X86_OP_NOT_BOOL = 2u;
static const uint X86_OP_ADD_I32 = 1u;
static const uint X86_OP_SUB_I32 = 2u;
static const uint X86_OP_MUL_I32 = 3u;
static const uint X86_OP_AND_BOOL = 4u;
static const uint X86_OP_OR_BOOL = 5u;
static const uint X86_OP_MOD_I32 = 6u;
static const uint X86_OP_DIV_I32 = 7u;
static const uint X86_OP_BIT_AND_I32 = 8u;
static const uint X86_OP_BIT_OR_I32 = 9u;
static const uint X86_OP_BIT_XOR = 10u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;
static const uint X86_REG_EAX = 0u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;
static const uint X86_REG_R10D = 10u;
static const uint X86_REG_R11D = 11u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint le32_byte(uint value, uint byte_i)
{
    return (value >> (byte_i * 8u)) & 0xffu;
}

uint abs_i32_magnitude(uint value)
{
    return (value & 0x80000000u) != 0u ? (0u - value) : value;
}

uint decimal_digit_count_u32(uint value)
{
    if (value < 10u) return 1u;
    if (value < 100u) return 2u;
    if (value < 1000u) return 3u;
    if (value < 10000u) return 4u;
    if (value < 100000u) return 5u;
    if (value < 1000000u) return 6u;
    if (value < 10000000u) return 7u;
    if (value < 100000000u) return 8u;
    if (value < 1000000000u) return 9u;
    return 10u;
}

uint pow10_u32(uint exp)
{
    uint value = 1u;
    [loop]
    for (uint i = 0u; i < 10u; i += 1u)
    {
        if (i >= exp)
            break;
        value *= 10u;
    }
    return value;
}

uint i32_text_byte(uint value, uint byte_i)
{
    bool negative = (value & 0x80000000u) != 0u;
    uint magnitude = abs_i32_magnitude(value);
    uint digits = decimal_digit_count_u32(magnitude);
    uint sign = negative ? 1u : 0u;
    uint total = sign + digits + 1u;
    if (negative && byte_i == 0u)
        return 45u;
    if (byte_i + 1u == total)
        return 10u;
    if (byte_i >= total)
        return 0u;

    uint digit_i = byte_i - sign;
    uint divisor = pow10_u32(digits - 1u - digit_i);
    return 48u + ((magnitude / divisor) % 10u);
}

uint false_jump_opcode(uint compare_op)
{
    uint base = compare_op & ~X86_CMP_UNSIGNED_FLAG;
    bool unsigned_mode = (compare_op & X86_CMP_UNSIGNED_FLAG) != 0u;
    if (base == X86_CMP_LT) return unsigned_mode ? 0x83u : 0x8du;
    if (base == X86_CMP_GT) return unsigned_mode ? 0x86u : 0x8eu;
    if (base == X86_CMP_LE) return unsigned_mode ? 0x87u : 0x8fu;
    if (base == X86_CMP_GE) return unsigned_mode ? 0x82u : 0x8cu;
    if (base == X86_CMP_EQ) return 0x85u;
    if (base == X86_CMP_NE) return 0x84u;
    return 0x85u;
}

uint setcc_opcode(uint compare_op)
{
    uint base = compare_op & ~X86_CMP_UNSIGNED_FLAG;
    bool unsigned_mode = (compare_op & X86_CMP_UNSIGNED_FLAG) != 0u;
    if (base == X86_CMP_LT) return unsigned_mode ? 0x92u : 0x9cu;
    if (base == X86_CMP_GT) return unsigned_mode ? 0x97u : 0x9fu;
    if (base == X86_CMP_LE) return unsigned_mode ? 0x96u : 0x9eu;
    if (base == X86_CMP_GE) return unsigned_mode ? 0x93u : 0x9du;
    if (base == X86_CMP_EQ) return 0x94u;
    if (base == X86_CMP_NE) return 0x95u;
    return 0x94u;
}

bool valid_reg(uint reg)
{
    return reg < 16u;
}

bool needs_rex_opcode_reg(uint reg)
{
    return reg >= 8u && reg < 16u;
}

bool needs_rex_modrm(uint reg_field, uint rm)
{
    return (reg_field >= 8u && reg_field < 16u) || (rm >= 8u && rm < 16u);
}

bool needs_rex_low8_modrm(uint reg_field, uint rm)
{
    return (reg_field >= 8u && reg_field < 16u) || (rm >= 4u && rm < 16u);
}

uint rex_opcode_reg(uint reg)
{
    return 0x40u | ((reg >> 3u) & 1u);
}

uint rex_modrm(uint reg_field, uint rm)
{
    return 0x40u | (((reg_field >> 3u) & 1u) << 2u) | ((rm >> 3u) & 1u);
}

uint rex_low8_modrm(uint reg_field, uint rm)
{
    return rex_modrm(reg_field, rm);
}

uint modrm(uint reg_field, uint rm)
{
    return 0xc0u | ((reg_field & 7u) << 3u) | (rm & 7u);
}

uint packed_reg_a(uint packed)
{
    return packed & 0xffu;
}

uint packed_reg_b(uint packed)
{
    return (packed >> 8u) & 0xffu;
}

uint target_offset(uint target)
{
    uint inst_count = text_status[3u];
    if (target == inst_count)
        return x86_text_len[0u];
    return x86_inst_byte_offset[target];
}

uint rel32_to_target(uint site_inst, uint target_inst)
{
    uint source_next = x86_inst_byte_offset[site_inst] + x86_inst_size[site_inst];
    return target_offset(target_inst) - source_next;
}

uint rel32_to_target_from(uint source_next, uint target_inst)
{
    return target_offset(target_inst) - source_next;
}

uint mov_r32_imm32_byte(uint dst, uint imm, uint byte_i)
{
    bool rex = needs_rex_opcode_reg(dst);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_opcode_reg(dst);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0xb8u + (dst & 7u);
    if (byte_i < cursor + 5u) return le32_byte(imm, byte_i - cursor - 1u);
    return 0u;
}

uint mov_r32_r32_byte(uint dst, uint src, uint byte_i)
{
    bool rex = needs_rex_modrm(src, dst);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(src, dst);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x89u;
    if (byte_i == cursor + 1u) return modrm(src, dst);
    return 0u;
}

uint alu_opcode(uint op)
{
    if (op == X86_OP_ADD_I32) return 0x01u;
    if (op == X86_OP_SUB_I32) return 0x29u;
    if (op == X86_OP_AND_BOOL || op == X86_OP_BIT_AND_I32) return 0x21u;
    if (op == X86_OP_OR_BOOL || op == X86_OP_BIT_OR_I32) return 0x09u;
    if (op == X86_OP_BIT_XOR) return 0x31u;
    return 0u;
}

uint alu_r32_r32_byte(uint op, uint dst, uint src, uint byte_i)
{
    bool rex = needs_rex_modrm(src, dst);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(src, dst);
        cursor += 1u;
    }
    if (op == X86_OP_MUL_I32)
    {
        if (byte_i == cursor) return 0x0fu;
        if (byte_i == cursor + 1u) return 0xafu;
        if (byte_i == cursor + 2u) return modrm(dst, src);
        return 0u;
    }

    uint opcode = alu_opcode(op);
    if (byte_i == cursor) return opcode;
    if (byte_i == cursor + 1u) return modrm(src, dst);
    return 0u;
}

uint cmp_r32_r32_byte(uint left, uint right, uint byte_i)
{
    bool rex = needs_rex_modrm(right, left);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(right, left);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x39u;
    if (byte_i == cursor + 1u) return modrm(right, left);
    return 0u;
}

uint test_r32_r32_byte(uint reg, uint byte_i)
{
    bool rex = needs_rex_modrm(reg, reg);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(reg, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x85u;
    if (byte_i == cursor + 1u) return modrm(reg, reg);
    return 0u;
}

uint neg_r32_byte(uint reg, uint byte_i)
{
    bool rex = needs_rex_modrm(3u, reg);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(3u, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0xf7u;
    if (byte_i == cursor + 1u) return modrm(3u, reg);
    return 0u;
}

uint idiv_r32_byte(uint reg, uint byte_i)
{
    bool rex = needs_rex_modrm(7u, reg);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(7u, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0xf7u;
    if (byte_i == cursor + 1u) return modrm(7u, reg);
    return 0u;
}

uint shift_r32_cl_byte(uint op, uint reg, uint byte_i)
{
    uint field = op == X86_OP_SHL_I32 ? 4u : 7u;
    bool rex = needs_rex_modrm(field, reg);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(field, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0xd3u;
    if (byte_i == cursor + 1u) return modrm(field, reg);
    return 0u;
}

uint movzx_r32_al_byte(uint dst, uint byte_i)
{
    bool rex = needs_rex_modrm(dst, X86_REG_EAX);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst, X86_REG_EAX);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return 0xb6u;
    if (byte_i == cursor + 2u) return modrm(dst, X86_REG_EAX);
    return 0u;
}

uint setcc_r8_byte(uint compare_op, uint dst, uint byte_i)
{
    bool rex = needs_rex_low8_modrm(0u, dst);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_low8_modrm(0u, dst);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return setcc_opcode(compare_op);
    if (byte_i == cursor + 2u) return modrm(0u, dst);
    return 0u;
}

uint movzx_r32_r8_byte(uint dst, uint byte_i)
{
    bool rex = needs_rex_low8_modrm(dst, dst);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_low8_modrm(dst, dst);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return 0xb6u;
    if (byte_i == cursor + 2u) return modrm(dst, dst);
    return 0u;
}

uint setcc_al_byte(uint compare_op, uint byte_i)
{
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return setcc_opcode(compare_op);
    if (byte_i == 2u) return 0xc0u;
    return 0u;
}

uint jz_target_byte(uint inst_i, uint target, uint byte_i)
{
    uint rel = rel32_to_target(inst_i, target);
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x84u;
    if (byte_i < 6u) return le32_byte(rel, byte_i - 2u);
    return 0u;
}

uint jmp_target_byte(uint inst_i, uint target, uint byte_i)
{
    uint rel = rel32_to_target(inst_i, target);
    if (byte_i == 0u) return 0xe9u;
    if (byte_i < 5u) return le32_byte(rel, byte_i - 1u);
    return 0u;
}

uint call_target_byte(uint inst_i, uint target, uint byte_i)
{
    uint rel = rel32_to_target(inst_i, target);
    if (byte_i == 0u) return 0xe8u;
    if (byte_i < 5u) return le32_byte(rel, byte_i - 1u);
    return 0u;
}

uint call_target_from_byte(uint source_next, uint target, uint byte_i)
{
    uint rel = rel32_to_target_from(source_next, target);
    if (byte_i == 0u) return 0xe8u;
    if (byte_i < 5u) return le32_byte(rel, byte_i - 1u);
    return 0u;
}

uint mov_r32_r32_size(uint dst, uint src)
{
    return 2u + (needs_rex_modrm(src, dst) ? 1u : 0u);
}

uint mov_r32_imm32_size(uint dst)
{
    return 5u + (needs_rex_opcode_reg(dst) ? 1u : 0u);
}

uint unary_macro_byte(uint op, uint dst, uint src, uint byte_i)
{
    if (op == X86_OP_NEG_I32)
    {
        uint move_size = dst == src ? 0u : mov_r32_r32_size(dst, src);
        if (byte_i < move_size)
            return mov_r32_r32_byte(dst, src, byte_i);
        byte_i -= move_size;
        return neg_r32_byte(dst, byte_i);
    }
    if (op == X86_OP_NOT_BOOL)
    {
        uint test_size = 2u + (needs_rex_modrm(src, src) ? 1u : 0u);
        if (byte_i < test_size)
            return test_r32_r32_byte(src, byte_i);
        byte_i -= test_size;
        uint set_size = 3u + (needs_rex_low8_modrm(0u, dst) ? 1u : 0u);
        if (byte_i < set_size)
            return setcc_r8_byte(X86_CMP_EQ, dst, byte_i);
        byte_i -= set_size;
        return movzx_r32_r8_byte(dst, byte_i);
    }
    return 0u;
}

uint binary_macro_byte(uint op, uint dst, uint packed, uint byte_i)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    if (op == X86_OP_DIV_I32 || op == X86_OP_MOD_I32)
    {
        uint right_move_size = right == X86_REG_ECX ? 0u : mov_r32_r32_size(X86_REG_ECX, right);
        if (byte_i < right_move_size)
            return mov_r32_r32_byte(X86_REG_ECX, right, byte_i);
        byte_i -= right_move_size;

        uint left_move_size = left == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, left);
        if (byte_i < left_move_size)
            return mov_r32_r32_byte(X86_REG_EAX, left, byte_i);
        byte_i -= left_move_size;

        if (byte_i == 0u)
            return 0x99u;
        byte_i -= 1u;

        uint idiv_size = 2u + (needs_rex_modrm(7u, X86_REG_ECX) ? 1u : 0u);
        if (byte_i < idiv_size)
            return idiv_r32_byte(X86_REG_ECX, byte_i);
        byte_i -= idiv_size;

        uint result = op == X86_OP_MOD_I32 ? X86_REG_EDX : X86_REG_EAX;
        return dst == result ? 0u : mov_r32_r32_byte(dst, result, byte_i);
    }

    uint move_size = dst == left ? 0u : mov_r32_r32_size(dst, left);
    if (byte_i < move_size)
        return mov_r32_r32_byte(dst, left, byte_i);
    byte_i -= move_size;

    if (op == X86_OP_SHL_I32 || op == X86_OP_SHR_I32)
    {
        uint count_move_size = right == X86_REG_ECX ? 0u : mov_r32_r32_size(X86_REG_ECX, right);
        if (byte_i < count_move_size)
            return mov_r32_r32_byte(X86_REG_ECX, right, byte_i);
        byte_i -= count_move_size;
        return shift_r32_cl_byte(op, dst, byte_i);
    }

    return alu_r32_r32_byte(op, dst, right, byte_i);
}

uint compare_macro_byte(uint compare_op, uint dst, uint packed, uint byte_i)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    uint cmp_size = 2u + (needs_rex_modrm(right, left) ? 1u : 0u);
    if (byte_i < cmp_size)
        return cmp_r32_r32_byte(left, right, byte_i);
    byte_i -= cmp_size;
    uint set_size = 3u + (needs_rex_low8_modrm(0u, dst) ? 1u : 0u);
    if (byte_i < set_size)
        return setcc_r8_byte(compare_op, dst, byte_i);
    byte_i -= set_size;
    return movzx_r32_r8_byte(dst, byte_i);
}

uint return_macro_byte(uint src, uint byte_i)
{
    uint move_size = src == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, src);
    if (byte_i < move_size)
        return mov_r32_r32_byte(X86_REG_EDI, src, byte_i);
    byte_i -= move_size;
    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_EAX, 60u, byte_i);
    byte_i -= 5u;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    return 0u;
}

uint return_func_macro_byte(uint src, uint byte_i)
{
    uint move_size = src == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, src);
    if (byte_i < move_size)
        return mov_r32_r32_byte(X86_REG_EAX, src, byte_i);
    byte_i -= move_size;
    if (byte_i == 0u) return 0xc3u;
    return 0u;
}

uint push_pop_reg_size(uint reg)
{
    return 1u + (needs_rex_opcode_reg(reg) ? 1u : 0u);
}

uint push_r64_byte(uint reg, uint byte_i)
{
    bool rex = needs_rex_opcode_reg(reg);
    if (rex)
    {
        if (byte_i == 0u) return rex_opcode_reg(reg);
        byte_i -= 1u;
    }
    return byte_i == 0u ? 0x50u + (reg & 7u) : 0u;
}

uint pop_r64_byte(uint reg, uint byte_i)
{
    bool rex = needs_rex_opcode_reg(reg);
    if (rex)
    {
        if (byte_i == 0u) return rex_opcode_reg(reg);
        byte_i -= 1u;
    }
    return byte_i == 0u ? 0x58u + (reg & 7u) : 0u;
}

uint call_saved_reg_for_slot(uint slot)
{
    if (slot == 0u) return X86_REG_ECX;
    if (slot == 1u) return X86_REG_EDX;
    if (slot == 2u) return X86_REG_ESI;
    if (slot == 3u) return X86_REG_EDI;
    if (slot == 4u) return X86_REG_R8D;
    if (slot == 5u) return X86_REG_R9D;
    if (slot == 6u) return X86_REG_R10D;
    if (slot == 7u) return X86_REG_R11D;
    return 0xffffffffu;
}

uint print_saved_reg_for_slot(uint slot)
{
    if (slot == 0u) return X86_REG_EAX;
    if (slot == 1u) return X86_REG_ECX;
    if (slot == 2u) return X86_REG_EDX;
    if (slot == 3u) return X86_REG_ESI;
    if (slot == 4u) return X86_REG_EDI;
    if (slot == 5u) return X86_REG_R8D;
    if (slot == 6u) return X86_REG_R9D;
    if (slot == 7u) return X86_REG_R10D;
    if (slot == 8u) return X86_REG_R11D;
    return 0xffffffffu;
}

uint call_save_restore_size()
{
    uint size = 0u;
    [unroll]
    for (uint slot = 0u; slot < 8u; slot += 1u)
        size += push_pop_reg_size(call_saved_reg_for_slot(slot));
    return size;
}

uint print_save_restore_size()
{
    uint size = 0u;
    [unroll]
    for (uint slot = 0u; slot < 9u; slot += 1u)
        size += push_pop_reg_size(print_saved_reg_for_slot(slot));
    return size;
}

uint call_save_regs_byte(uint byte_i)
{
    [unroll]
    for (uint slot = 0u; slot < 8u; slot += 1u)
    {
        uint reg = call_saved_reg_for_slot(slot);
        uint size = push_pop_reg_size(reg);
        if (byte_i < size)
            return push_r64_byte(reg, byte_i);
        byte_i -= size;
    }
    return 0u;
}

uint print_save_regs_byte(uint byte_i)
{
    [unroll]
    for (uint slot = 0u; slot < 9u; slot += 1u)
    {
        uint reg = print_saved_reg_for_slot(slot);
        uint size = push_pop_reg_size(reg);
        if (byte_i < size)
            return push_r64_byte(reg, byte_i);
        byte_i -= size;
    }
    return 0u;
}

uint print_restore_regs_byte(uint byte_i)
{
    [unroll]
    for (uint slot = 0u; slot < 9u; slot += 1u)
    {
        uint reg = print_saved_reg_for_slot(8u - slot);
        uint size = push_pop_reg_size(reg);
        if (byte_i < size)
            return pop_r64_byte(reg, byte_i);
        byte_i -= size;
    }
    return 0u;
}

uint call_restore_regs_byte(uint byte_i)
{
    [unroll]
    for (uint slot = 0u; slot < 8u; slot += 1u)
    {
        uint reg = call_saved_reg_for_slot(7u - slot);
        uint size = push_pop_reg_size(reg);
        if (byte_i < size)
            return pop_r64_byte(reg, byte_i);
        byte_i -= size;
    }
    return 0u;
}

uint alu_r64_rsp_imm8_byte(uint sub_op, uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x48u;
    if (byte_i == 1u) return 0x83u;
    if (byte_i == 2u) return sub_op != 0u ? 0xecu : 0xc4u;
    if (byte_i == 3u) return imm & 0xffu;
    return 0u;
}

uint lea_rsi_rsp_disp8_byte(uint disp, uint byte_i)
{
    if (byte_i == 0u) return 0x48u;
    if (byte_i == 1u) return 0x8du;
    if (byte_i == 2u) return 0x74u;
    if (byte_i == 3u) return 0x24u;
    if (byte_i == 4u) return disp & 0xffu;
    return 0u;
}

uint mov_m8_rsi_imm8_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0xc6u;
    if (byte_i == 1u) return 0x06u;
    if (byte_i == 2u) return imm & 0xffu;
    return 0u;
}

uint sub_rsi_imm8_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x48u;
    if (byte_i == 1u) return 0x83u;
    if (byte_i == 2u) return 0xeeu;
    if (byte_i == 3u) return imm & 0xffu;
    return 0u;
}

uint add_r32_imm8_byte(uint reg, uint imm, uint byte_i)
{
    bool rex = needs_rex_modrm(0u, reg);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(0u, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x83u;
    if (byte_i == cursor + 1u) return modrm(0u, reg);
    if (byte_i == cursor + 2u) return imm & 0xffu;
    return 0u;
}

uint xor_r32_r32_byte(uint reg, uint byte_i)
{
    bool rex = needs_rex_modrm(reg, reg);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(reg, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x31u;
    if (byte_i == cursor + 1u) return modrm(reg, reg);
    return 0u;
}

uint div_r32_byte(uint reg, uint byte_i)
{
    bool rex = needs_rex_modrm(6u, reg);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(6u, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0xf7u;
    if (byte_i == cursor + 1u) return modrm(6u, reg);
    return 0u;
}

uint jcc_rel8_byte(uint opcode, uint rel, uint byte_i)
{
    if (byte_i == 0u) return opcode;
    if (byte_i == 1u) return rel & 0xffu;
    return 0u;
}

uint mov_m8_rsi_dl_byte(uint byte_i)
{
    if (byte_i == 0u) return 0x88u;
    if (byte_i == 1u) return 0x16u;
    return 0u;
}

uint call_arg_move_size(uint arg_count, uint arg0, uint arg1)
{
    if (arg_count == 0u)
        return 0u;
    if (arg_count == 1u)
        return arg0 == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, arg0);
    if (arg0 == X86_REG_ESI && arg1 == X86_REG_EDI)
    {
        return mov_r32_r32_size(X86_REG_EAX, X86_REG_EDI) +
               mov_r32_r32_size(X86_REG_EDI, X86_REG_ESI) +
               mov_r32_r32_size(X86_REG_ESI, X86_REG_EAX);
    }

    uint size = 0u;
    if (arg0 != X86_REG_EDI)
        size += mov_r32_r32_size(X86_REG_EDI, arg0);
    if (arg1 != X86_REG_ESI)
        size += mov_r32_r32_size(X86_REG_ESI, arg1);
    return size;
}

uint call_arg_moves_byte(uint arg_count, uint arg0, uint arg1, uint byte_i)
{
    if (arg_count == 0u)
        return 0u;

    if (arg_count == 1u)
        return arg0 == X86_REG_EDI ? 0u : mov_r32_r32_byte(X86_REG_EDI, arg0, byte_i);

    if (arg0 == X86_REG_ESI && arg1 == X86_REG_EDI)
    {
        uint save_size = mov_r32_r32_size(X86_REG_EAX, X86_REG_EDI);
        if (byte_i < save_size)
            return mov_r32_r32_byte(X86_REG_EAX, X86_REG_EDI, byte_i);
        byte_i -= save_size;

        uint move0_size = mov_r32_r32_size(X86_REG_EDI, X86_REG_ESI);
        if (byte_i < move0_size)
            return mov_r32_r32_byte(X86_REG_EDI, X86_REG_ESI, byte_i);
        byte_i -= move0_size;

        return mov_r32_r32_byte(X86_REG_ESI, X86_REG_EAX, byte_i);
    }

    uint move0_size = arg0 == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, arg0);
    uint move1_size = arg1 == X86_REG_ESI ? 0u : mov_r32_r32_size(X86_REG_ESI, arg1);
    bool move1_first = arg1 == X86_REG_EDI && arg0 != X86_REG_ESI;

    if (move1_first)
    {
        if (byte_i < move1_size)
            return mov_r32_r32_byte(X86_REG_ESI, arg1, byte_i);
        byte_i -= move1_size;
        return byte_i < move0_size ? mov_r32_r32_byte(X86_REG_EDI, arg0, byte_i) : 0u;
    }

    if (byte_i < move0_size)
        return mov_r32_r32_byte(X86_REG_EDI, arg0, byte_i);
    byte_i -= move0_size;
    return byte_i < move1_size ? mov_r32_r32_byte(X86_REG_ESI, arg1, byte_i) : 0u;
}

uint call_direct_macro_byte(uint inst_i, uint target, uint dst, uint packed, uint byte_i)
{
    uint arg_count = packed & 0xffu;
    uint arg0 = (packed >> 8u) & 0xffu;
    uint arg1 = (packed >> 16u) & 0xffu;
    uint save_size = call_save_restore_size();
    if (byte_i < save_size)
        return call_save_regs_byte(byte_i);
    byte_i -= save_size;

    uint arg_move_size = call_arg_move_size(arg_count, arg0, arg1);
    if (byte_i < arg_move_size)
        return call_arg_moves_byte(arg_count, arg0, arg1, byte_i);
    byte_i -= arg_move_size;

    if (byte_i < 5u)
    {
        uint call_next = x86_inst_byte_offset[inst_i] + save_size + arg_move_size + 5u;
        return call_target_from_byte(call_next, target, byte_i);
    }
    byte_i -= 5u;

    if (byte_i < save_size)
        return call_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint print_i32_macro_byte(uint src, uint byte_i)
{
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint src_move_size = src == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, src);
    if (byte_i < src_move_size)
        return mov_r32_r32_byte(X86_REG_EAX, src, byte_i);
    byte_i -= src_move_size;

    if (byte_i < 6u)
        return mov_r32_imm32_byte(X86_REG_R10D, 10u, byte_i);
    byte_i -= 6u;

    if (byte_i < 5u)
        return lea_rsi_rsp_disp8_byte(15u, byte_i);
    byte_i -= 5u;

    if (byte_i < 3u)
        return mov_m8_rsi_imm8_byte(10u, byte_i);
    byte_i -= 3u;

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_ECX, 1u, byte_i);
    byte_i -= 5u;

    if (byte_i < 3u)
        return xor_r32_r32_byte(X86_REG_R11D, byte_i);
    byte_i -= 3u;

    if (byte_i < 2u)
        return test_r32_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= 2u;

    if (byte_i < 2u)
        return jcc_rel8_byte(0x79u, 8u, byte_i);
    byte_i -= 2u;

    if (byte_i < 2u)
        return neg_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= 2u;

    if (byte_i < 6u)
        return mov_r32_imm32_byte(X86_REG_R11D, 1u, byte_i);
    byte_i -= 6u;

    if (byte_i < 2u)
        return xor_r32_r32_byte(X86_REG_EDX, byte_i);
    byte_i -= 2u;

    if (byte_i < 3u)
        return div_r32_byte(X86_REG_R10D, byte_i);
    byte_i -= 3u;

    if (byte_i < 3u)
        return add_r32_imm8_byte(X86_REG_EDX, 48u, byte_i);
    byte_i -= 3u;

    if (byte_i < 4u)
        return sub_rsi_imm8_byte(1u, byte_i);
    byte_i -= 4u;

    if (byte_i < 2u)
        return mov_m8_rsi_dl_byte(byte_i);
    byte_i -= 2u;

    if (byte_i < 3u)
        return add_r32_imm8_byte(X86_REG_ECX, 1u, byte_i);
    byte_i -= 3u;

    if (byte_i < 2u)
        return test_r32_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= 2u;

    if (byte_i < 2u)
        return jcc_rel8_byte(0x75u, 235u, byte_i);
    byte_i -= 2u;

    if (byte_i < 3u)
        return test_r32_r32_byte(X86_REG_R11D, byte_i);
    byte_i -= 3u;

    if (byte_i < 2u)
        return jcc_rel8_byte(0x74u, 10u, byte_i);
    byte_i -= 2u;

    if (byte_i < 4u)
        return sub_rsi_imm8_byte(1u, byte_i);
    byte_i -= 4u;

    if (byte_i < 3u)
        return mov_m8_rsi_imm8_byte(45u, byte_i);
    byte_i -= 3u;

    if (byte_i < 3u)
        return add_r32_imm8_byte(X86_REG_ECX, 1u, byte_i);
    byte_i -= 3u;

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_EAX, 1u, byte_i);
    byte_i -= 5u;

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_EDI, 1u, byte_i);
    byte_i -= 5u;

    if (byte_i < 2u)
        return mov_r32_r32_byte(X86_REG_EDX, X86_REG_ECX, byte_i);
    byte_i -= 2u;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    return 0u;
}

uint instruction_byte(uint inst_i, uint byte_i)
{
    uint kind = x86_inst_kind[inst_i];
    if (kind == X86_INST_MOV_EAX_IMM32)
    {
        if (byte_i == 0u) return 0xb8u;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_MOV_EDI_IMM32)
    {
        if (byte_i == 0u) return 0xbfu;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_SYSCALL)
    {
        if (byte_i == 0u) return 0x0fu;
        if (byte_i == 1u) return 0x05u;
    }
    if (kind == X86_INST_ADD_EAX_IMM32)
    {
        if (byte_i == 0u) return 0x05u;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_SUB_EAX_IMM32)
    {
        if (byte_i == 0u) return 0x2du;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_IMUL_EAX_EAX_IMM32)
    {
        if (byte_i == 0u) return 0x69u;
        if (byte_i == 1u) return 0xc0u;
        if (byte_i < 6u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 2u);
    }
    if (kind == X86_INST_MOV_EDI_EAX)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xc7u;
    }
    if (kind == X86_INST_CMP_EAX_IMM32)
    {
        if (byte_i == 0u) return 0x3du;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_JCC_FALSE_REL32)
    {
        if (byte_i == 0u) return 0x0fu;
        if (byte_i == 1u) return false_jump_opcode(x86_inst_arg0[inst_i]);
        if (byte_i < 6u) return 0u;
    }
    if (kind == X86_INST_JMP_REL32)
    {
        if (byte_i == 0u) return 0xe9u;
        if (byte_i < 5u) return 0u;
    }
    if (kind == X86_INST_SETCC_AL)
    {
        if (byte_i == 0u) return 0x0fu;
        if (byte_i == 1u) return setcc_opcode(x86_inst_arg0[inst_i]);
        if (byte_i == 2u) return 0xc0u;
    }
    if (kind == X86_INST_MOVZX_EDI_AL)
    {
        if (byte_i == 0u) return 0x0fu;
        if (byte_i == 1u) return 0xb6u;
        if (byte_i == 2u) return 0xf8u;
    }
    if (kind == X86_INST_AND_EAX_IMM32)
    {
        if (byte_i == 0u) return 0x25u;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_OR_EAX_IMM32)
    {
        if (byte_i == 0u) return 0x0du;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_CALL_REL32)
    {
        if (byte_i == 0u) return 0xe8u;
        if (byte_i < 5u) return 0u;
    }
    if (kind == X86_INST_MOV_ESI_TEXT_ROW_ADDR)
    {
        uint data_inst = x86_inst_arg0[inst_i];
        uint data_addr = X86_TEXT_VADDR + x86_inst_byte_offset[data_inst];
        if (byte_i == 0u) return 0xbeu;
        if (byte_i < 5u) return le32_byte(data_addr, byte_i - 1u);
    }
    if (kind == X86_INST_DATA_I32_NL)
        return i32_text_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_RET)
    {
        if (byte_i == 0u) return 0xc3u;
    }
    if (kind == X86_INST_MOV_EAX_EDI)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xf8u;
    }
    if (kind == X86_INST_MOV_ESI_IMM32)
    {
        if (byte_i == 0u) return 0xbeu;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_ADD_EAX_ESI)
    {
        if (byte_i == 0u) return 0x01u;
        if (byte_i == 1u) return 0xf0u;
    }
    if (kind == X86_INST_SUB_EAX_ESI)
    {
        if (byte_i == 0u) return 0x29u;
        if (byte_i == 1u) return 0xf0u;
    }
    if (kind == X86_INST_IMUL_EAX_ESI)
    {
        if (byte_i == 0u) return 0x0fu;
        if (byte_i == 1u) return 0xafu;
        if (byte_i == 2u) return 0xc6u;
    }
    if (kind == X86_INST_AND_EAX_ESI)
    {
        if (byte_i == 0u) return 0x21u;
        if (byte_i == 1u) return 0xf0u;
    }
    if (kind == X86_INST_OR_EAX_ESI)
    {
        if (byte_i == 0u) return 0x09u;
        if (byte_i == 1u) return 0xf0u;
    }
    if (kind == X86_INST_MOV_ESI_EAX)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xc6u;
    }
    if (kind == X86_INST_MOV_EAX_ESI)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xf0u;
    }
    if (kind == X86_INST_MOV_EAX_EDX)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xd0u;
    }
    if (kind == X86_INST_MOV_EDX_IMM32)
    {
        if (byte_i == 0u) return 0xbau;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_CMP_EAX_ESI)
    {
        if (byte_i == 0u) return 0x39u;
        if (byte_i == 1u) return 0xf0u;
    }
    if (kind == X86_INST_NEG_EAX)
    {
        if (byte_i == 0u) return 0xf7u;
        if (byte_i == 1u) return 0xd8u;
    }
    if (kind == X86_INST_MOVZX_EAX_AL)
    {
        if (byte_i == 0u) return 0x0fu;
        if (byte_i == 1u) return 0xb6u;
        if (byte_i == 2u) return 0xc0u;
    }
    if (kind == X86_INST_CMP_EAX_EDX)
    {
        if (byte_i == 0u) return 0x39u;
        if (byte_i == 1u) return 0xd0u;
    }
    if (kind == X86_INST_CDQ)
    {
        if (byte_i == 0u) return 0x99u;
    }
    if (kind == X86_INST_MOV_ECX_IMM32)
    {
        if (byte_i == 0u) return 0xb9u;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_IDIV_ECX)
    {
        if (byte_i == 0u) return 0xf7u;
        if (byte_i == 1u) return 0xf9u;
    }
    if (kind == X86_INST_MOV_EDI_EDX)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xd7u;
    }
    if (kind == X86_INST_MOV_ECX_EAX)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xc1u;
    }
    if (kind == X86_INST_AND_EAX_ECX)
    {
        if (byte_i == 0u) return 0x21u;
        if (byte_i == 1u) return 0xc8u;
    }
    if (kind == X86_INST_OR_EAX_ECX)
    {
        if (byte_i == 0u) return 0x09u;
        if (byte_i == 1u) return 0xc8u;
    }
    if (kind == X86_INST_XOR_EAX_IMM32)
    {
        if (byte_i == 0u) return 0x35u;
        if (byte_i < 5u) return le32_byte(x86_inst_arg0[inst_i], byte_i - 1u);
    }
    if (kind == X86_INST_SHL_EAX_IMM8)
    {
        if (byte_i == 0u) return 0xc1u;
        if (byte_i == 1u) return 0xe0u;
        if (byte_i == 2u) return x86_inst_arg0[inst_i] & 0xffu;
    }
    if (kind == X86_INST_SAR_EAX_IMM8)
    {
        if (byte_i == 0u) return 0xc1u;
        if (byte_i == 1u) return 0xf8u;
        if (byte_i == 2u) return x86_inst_arg0[inst_i] & 0xffu;
    }
    if (kind == X86_INST_XOR_EAX_ESI)
    {
        if (byte_i == 0u) return 0x31u;
        if (byte_i == 1u) return 0xf0u;
    }
    if (kind == X86_INST_MOV_ESI_EDI)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xfeu;
    }
    if (kind == X86_INST_MOV_EDX_EDI)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xfau;
    }
    if (kind == X86_INST_MOV_EDI_ESI)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xf7u;
    }
    if (kind == X86_INST_MOV_EDX_ESI)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xf2u;
    }
    if (kind == X86_INST_MOV_ESI_EDX)
    {
        if (byte_i == 0u) return 0x89u;
        if (byte_i == 1u) return 0xd6u;
    }
    if (kind == X86_INST_V_MOV_R32_IMM32)
        return mov_r32_imm32_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_MOV_R32_R32)
        return mov_r32_r32_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_UNARY_R32)
        return unary_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_BINARY_R32_R32)
        return binary_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_COMPARE_R32_R32)
        return compare_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_RETURN_R32)
        return return_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_BRANCH_ZERO)
    {
        uint cond = x86_inst_arg0[inst_i];
        uint test_size = 2u + (needs_rex_modrm(cond, cond) ? 1u : 0u);
        if (byte_i < test_size)
            return test_r32_r32_byte(cond, byte_i);
        return jz_target_byte(inst_i, x86_inst_arg1[inst_i], byte_i - test_size);
    }
    if (kind == X86_INST_V_JMP)
        return jmp_target_byte(inst_i, x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_PARAM_R32)
        return mov_r32_r32_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_CALL_DIRECT)
        return call_direct_macro_byte(
            inst_i,
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_RETURN_FUNC_R32)
        return return_func_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_PRINT_I32)
        return print_i32_macro_byte(x86_inst_arg0[inst_i], byte_i);
    return 0u;
}

uint text_byte(uint pos)
{
    if (pos >= x86_text_len[0u])
        return 0u;

    uint inst_count = text_status[3u];
    [loop]
    for (uint inst_i = 0u; inst_i < inst_count; inst_i += 1u)
    {
        uint offset = x86_inst_byte_offset[inst_i];
        uint size = x86_inst_size[inst_i];
        if (pos >= offset && pos < offset + size)
            return instruction_byte(inst_i, pos - offset);
    }
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word_i = linear_dispatch_id(tid);
    bool text_ok = text_status[0u] == X86_TEXT_OK && text_status[1u] == 0u;
    uint text_len = text_ok ? x86_text_len[0u] : 0u;
    uint word_count = (text_len + 3u) / 4u;

    if (word_i == 0u)
    {
        encode_status[0u] = text_ok ? X86_ENCODE_OK : 0u;
        encode_status[1u] = text_ok ? 0u : text_status[1u];
        encode_status[2u] = text_ok ? 0xffffffffu : text_status[2u];
        encode_status[3u] = text_len;
    }

    if (!text_ok || word_i >= word_count)
        return;

    uint pos = word_i * 4u;
    uint b0 = text_byte(pos + 0u);
    uint b1 = text_byte(pos + 1u);
    uint b2 = text_byte(pos + 2u);
    uint b3 = text_byte(pos + 3u);
    x86_text_words[word_i] = b0 | (b1 << 8u) | (b2 << 16u) | (b3 << 24u);
}
