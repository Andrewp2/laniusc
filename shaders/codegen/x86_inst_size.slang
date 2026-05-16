// Direct x86_64 instruction sizing for the first native backend slice.
//
// x86_64 instructions are variable width, so byte sizes are GPU records instead
// of constants baked into the ELF writer.

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
StructuredBuffer<uint> select_status;

RWStructuredBuffer<uint> x86_inst_size;
RWStructuredBuffer<uint> size_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_SELECT_OK = 1u;
static const uint X86_SIZE_OK = 1u;
static const uint X86_ERR_INST_SIZE = 6u;

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

uint i32_text_len(uint value)
{
    uint digits = decimal_digit_count_u32(abs_i32_magnitude(value));
    uint sign = (value & 0x80000000u) != 0u ? 1u : 0u;
    return sign + digits + 1u;
}

bool valid_reg(uint reg)
{
    return reg < 16u;
}

uint rex_for_opcode_reg(uint reg)
{
    return reg >= 8u && reg < 16u ? 1u : 0u;
}

uint rex_for_modrm(uint reg_field, uint rm)
{
    return (reg_field >= 8u && reg_field < 16u) || (rm >= 8u && rm < 16u) ? 1u : 0u;
}

uint rex_for_low8_modrm(uint reg_field, uint rm)
{
    return (reg_field >= 8u && reg_field < 16u) || (rm >= 4u && rm < 16u) ? 1u : 0u;
}

uint packed_reg_a(uint packed)
{
    return packed & 0xffu;
}

uint packed_reg_b(uint packed)
{
    return (packed >> 8u) & 0xffu;
}

uint mov_r32_imm32_size(uint dst)
{
    return valid_reg(dst) ? 5u + rex_for_opcode_reg(dst) : 0u;
}

uint mov_r32_r32_size(uint dst, uint src)
{
    return valid_reg(dst) && valid_reg(src) ? 2u + rex_for_modrm(src, dst) : 0u;
}

uint unary_size(uint op, uint dst, uint src)
{
    if (!valid_reg(dst) || !valid_reg(src))
        return 0u;
    uint move_size = dst == src ? 0u : mov_r32_r32_size(dst, src);
    if (op == X86_OP_NEG_I32)
        return move_size + 2u + rex_for_modrm(3u, dst);
    if (op == X86_OP_NOT_BOOL)
        return 2u + rex_for_modrm(src, src) +
               3u + rex_for_low8_modrm(0u, dst) +
               3u + rex_for_low8_modrm(dst, dst);
    return 0u;
}

uint binary_alu_size(uint op, uint dst, uint right)
{
    if (!valid_reg(dst) || !valid_reg(right))
        return 0u;
    if (op == X86_OP_MUL_I32)
        return 3u + rex_for_modrm(dst, right);
    if (op == X86_OP_ADD_I32 ||
        op == X86_OP_SUB_I32 ||
        op == X86_OP_AND_BOOL ||
        op == X86_OP_OR_BOOL ||
        op == X86_OP_BIT_AND_I32 ||
        op == X86_OP_BIT_OR_I32 ||
        op == X86_OP_BIT_XOR)
        return 2u + rex_for_modrm(right, dst);
    if (op == X86_OP_SHL_I32 || op == X86_OP_SHR_I32)
        return (right == X86_REG_ECX ? 0u : mov_r32_r32_size(X86_REG_ECX, right)) +
               2u + rex_for_modrm(op == X86_OP_SHL_I32 ? 4u : 7u, dst);
    return 0u;
}

uint divmod_size(uint op, uint dst, uint left, uint right)
{
    if (op != X86_OP_DIV_I32 && op != X86_OP_MOD_I32)
        return 0u;
    if (!valid_reg(dst) || !valid_reg(left) || !valid_reg(right))
        return 0u;

    uint size = 0u;
    if (right != X86_REG_ECX)
        size += mov_r32_r32_size(X86_REG_ECX, right);
    if (left != X86_REG_EAX)
        size += mov_r32_r32_size(X86_REG_EAX, left);
    size += 1u;
    size += 2u + rex_for_modrm(7u, X86_REG_ECX);
    uint result = op == X86_OP_MOD_I32 ? X86_REG_EDX : X86_REG_EAX;
    if (dst != result)
        size += mov_r32_r32_size(dst, result);
    return size;
}

uint binary_size(uint op, uint dst, uint packed)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    if (!valid_reg(dst) || !valid_reg(left) || !valid_reg(right))
        return 0u;
    if (op == X86_OP_DIV_I32 || op == X86_OP_MOD_I32)
        return divmod_size(op, dst, left, right);

    uint move_size = dst == left ? 0u : mov_r32_r32_size(dst, left);
    uint op_size = binary_alu_size(op, dst, right);
    return op_size == 0u ? 0u : move_size + op_size;
}

uint compare_size(uint dst, uint packed)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    if (!valid_reg(dst) || !valid_reg(left) || !valid_reg(right))
        return 0u;
    return 2u + rex_for_modrm(right, left) +
           3u + rex_for_low8_modrm(0u, dst) +
           3u + rex_for_low8_modrm(dst, dst);
}

uint branch_zero_size(uint cond)
{
    return valid_reg(cond) ? 2u + rex_for_modrm(cond, cond) + 6u : 0u;
}

uint return_size(uint src)
{
    if (!valid_reg(src))
        return 0u;
    uint move_size = src == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, src);
    return move_size + 5u + 2u;
}

uint return_func_size(uint src)
{
    if (!valid_reg(src))
        return 0u;
    uint move_size = src == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, src);
    return move_size + 1u;
}

uint push_pop_reg_size(uint reg)
{
    return valid_reg(reg) ? 1u + rex_for_opcode_reg(reg) : 0u;
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

uint print_i32_size(uint src)
{
    if (!valid_reg(src))
        return 0u;
    uint src_move = src == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, src);
    return print_save_restore_size() + 92u + src_move + print_save_restore_size();
}

uint call_arg_move_size(uint arg_count, uint arg0, uint arg1)
{
    if (arg_count == 0u)
        return 0u;
    if (arg_count == 1u)
        return valid_reg(arg0) ? (arg0 == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, arg0)) : 0u;
    if (!valid_reg(arg0) || !valid_reg(arg1))
        return 0u;

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

uint call_direct_size(uint dst, uint packed)
{
    uint arg_count = packed & 0xffu;
    uint arg0 = (packed >> 8u) & 0xffu;
    uint arg1 = (packed >> 16u) & 0xffu;
    if (!valid_reg(dst) || arg_count > 2u)
        return 0u;

    uint move_size = call_arg_move_size(arg_count, arg0, arg1);
    if ((arg_count > 0u && move_size == 0u && arg0 != X86_REG_EDI) ||
        (arg_count > 1u && !valid_reg(arg1)))
        return 0u;

    uint save_restore_size = call_save_restore_size();
    uint size = save_restore_size + move_size + 5u + save_restore_size;
    if (dst != X86_REG_EAX)
        size += mov_r32_r32_size(dst, X86_REG_EAX);
    return size;
}

uint byte_size_for_inst(uint inst_i)
{
    uint kind = x86_inst_kind[inst_i];
    if (kind == X86_INST_MOV_EAX_IMM32) return 5u;
    if (kind == X86_INST_MOV_EDI_IMM32) return 5u;
    if (kind == X86_INST_SYSCALL) return 2u;
    if (kind == X86_INST_ADD_EAX_IMM32) return 5u;
    if (kind == X86_INST_SUB_EAX_IMM32) return 5u;
    if (kind == X86_INST_IMUL_EAX_EAX_IMM32) return 6u;
    if (kind == X86_INST_MOV_EDI_EAX) return 2u;
    if (kind == X86_INST_CMP_EAX_IMM32) return 5u;
    if (kind == X86_INST_JCC_FALSE_REL32) return 6u;
    if (kind == X86_INST_JMP_REL32) return 5u;
    if (kind == X86_INST_SETCC_AL) return 3u;
    if (kind == X86_INST_MOVZX_EDI_AL) return 3u;
    if (kind == X86_INST_AND_EAX_IMM32) return 5u;
    if (kind == X86_INST_OR_EAX_IMM32) return 5u;
    if (kind == X86_INST_CALL_REL32) return 5u;
    if (kind == X86_INST_RET) return 1u;
    if (kind == X86_INST_MOV_EAX_EDI) return 2u;
    if (kind == X86_INST_MOV_ESI_IMM32) return 5u;
    if (kind == X86_INST_ADD_EAX_ESI) return 2u;
    if (kind == X86_INST_SUB_EAX_ESI) return 2u;
    if (kind == X86_INST_IMUL_EAX_ESI) return 3u;
    if (kind == X86_INST_AND_EAX_ESI) return 2u;
    if (kind == X86_INST_OR_EAX_ESI) return 2u;
    if (kind == X86_INST_MOV_ESI_EAX) return 2u;
    if (kind == X86_INST_MOV_EAX_ESI) return 2u;
    if (kind == X86_INST_MOV_EAX_EDX) return 2u;
    if (kind == X86_INST_MOV_EDX_IMM32) return 5u;
    if (kind == X86_INST_CMP_EAX_ESI) return 2u;
    if (kind == X86_INST_NEG_EAX) return 2u;
    if (kind == X86_INST_MOVZX_EAX_AL) return 3u;
    if (kind == X86_INST_CMP_EAX_EDX) return 2u;
    if (kind == X86_INST_CDQ) return 1u;
    if (kind == X86_INST_MOV_ECX_IMM32) return 5u;
    if (kind == X86_INST_IDIV_ECX) return 2u;
    if (kind == X86_INST_MOV_EDI_EDX) return 2u;
    if (kind == X86_INST_MOV_ECX_EAX) return 2u;
    if (kind == X86_INST_AND_EAX_ECX) return 2u;
    if (kind == X86_INST_OR_EAX_ECX) return 2u;
    if (kind == X86_INST_XOR_EAX_IMM32) return 5u;
    if (kind == X86_INST_SHL_EAX_IMM8) return 3u;
    if (kind == X86_INST_SAR_EAX_IMM8) return 3u;
    if (kind == X86_INST_XOR_EAX_ESI) return 2u;
    if (kind == X86_INST_MOV_ESI_EDI) return 2u;
    if (kind == X86_INST_MOV_EDX_EDI) return 2u;
    if (kind == X86_INST_MOV_EDI_ESI) return 2u;
    if (kind == X86_INST_MOV_EDX_ESI) return 2u;
    if (kind == X86_INST_MOV_ESI_EDX) return 2u;
    if (kind == X86_INST_DATA_I32_NL) return i32_text_len(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_MOV_ESI_TEXT_ROW_ADDR) return 5u;
    if (kind == X86_INST_V_MOV_R32_IMM32) return mov_r32_imm32_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_MOV_R32_R32) return mov_r32_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_UNARY_R32) return unary_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_BINARY_R32_R32) return binary_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_COMPARE_R32_R32) return compare_size(x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_RETURN_R32) return return_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_BRANCH_ZERO) return branch_zero_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_JMP) return 5u;
    if (kind == X86_INST_V_PARAM_R32) return mov_r32_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_CALL_DIRECT) return call_direct_size(x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_RETURN_FUNC_R32) return return_func_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_PRINT_I32) return print_i32_size(x86_inst_arg0[inst_i]);
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint inst_i = linear_dispatch_id(tid);
    bool select_ok = select_status[0u] == X86_SELECT_OK;
    uint inst_count = select_ok ? select_status[3u] : 0u;

    if (inst_i == 0u)
    {
        size_status[0u] = select_ok ? X86_SIZE_OK : 0u;
        size_status[1u] = select_ok ? 0u : select_status[1u];
        size_status[2u] = select_ok ? 0xffffffffu : select_status[2u];
        size_status[3u] = inst_count;
    }

    if (!select_ok || inst_i >= inst_count)
        return;

    uint size = byte_size_for_inst(inst_i);
    x86_inst_size[inst_i] = size;
    if (size == 0u)
    {
        size_status[0u] = 0u;
        size_status[1u] = X86_ERR_INST_SIZE;
        uint old_detail = 0u;
        InterlockedMin(size_status[2u], inst_i, old_detail);
    }
}
