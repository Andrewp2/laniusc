// Direct x86_64 instruction sizing for the first native backend slice.
//
// x86_64 instructions are variable width, so byte sizes are GPU records instead
// of constants baked into the ELF writer.

import gpu_index;
import byte_packing;
import bit_packing;
import status;
struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_inst_kind;
StructuredBuffer<uint> x86_inst_arg0;
StructuredBuffer<uint> x86_inst_arg1;
StructuredBuffer<uint> x86_inst_arg2;
StructuredBuffer<uint> x86_decl_layout_status;
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
static const uint X86_INST_V_RETURN_FUNC_R32 = 60u;
static const uint X86_INST_V_PRINT_I32 = 61u;
static const uint X86_INST_V_LOAD_LOCAL_R32 = 62u;
static const uint X86_INST_V_STORE_LOCAL_R32 = 63u;
static const uint X86_INST_V_ENTRY_STACK_JMP = 64u;
static const uint X86_INST_V_EXIT_ZERO = 65u;
static const uint X86_INST_V_LOAD_LOCAL_INDEX_R32 = 66u;
static const uint X86_INST_V_STORE_LOCAL_IMM32 = 67u;
static const uint X86_INST_V_FOR_ARRAY_BRANCH = 68u;
static const uint X86_INST_V_FOR_ARRAY_LOAD = 69u;
static const uint X86_INST_V_FOR_ARRAY_INC_JMP = 70u;
static const uint X86_INST_V_CALL_MIXED_DIRECT = 71u;
static const uint X86_INST_V_LOAD_PARAM_INDEX_R32 = 72u;
static const uint X86_INST_V_STORE_RET_PTR_R32 = 73u;
static const uint X86_INST_V_COPY_AGG_RET = 74u;
static const uint X86_INST_V_STORE_RET_PTR_IMM32 = 75u;
static const uint X86_INST_V_LOAD_PTR_SLOT_R32 = 76u;
static const uint X86_INST_V_MATCH_TAG_BRANCH = 77u;
static const uint X86_INST_V_FOR_INTERVAL_BRANCH = 78u;
static const uint X86_INST_V_COPY_LOCAL_R32 = 79u;
static const uint X86_ARG_SCALAR = 1u;
static const uint X86_ARG_LOCAL_PTR = 2u;
static const uint X86_ARG_PARAM_PTR = 3u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;
// Keep local-slot displacements within x86 signed disp32 while allowing large
// generated functions to exceed the old 16-bit-era guard.
static const uint MAX_X86_LOCAL_SLOTS = 1000000u;
static const uint MIN_X86_STACK_FRAME_BYTES = 16u;

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
static const uint X86_REG_EBX = 3u;
static const uint X86_REG_ESP = 4u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;
static const uint X86_REG_R10D = 10u;
static const uint X86_REG_R11D = 11u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
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

uint rex_for_sib(uint reg_field, uint index, uint base)
{
    return (reg_field >= 8u && reg_field < 16u) ||
           (index >= 8u && index < 16u) ||
           (base >= 8u && base < 16u) ? 1u : 0u;
}

uint rex_for_low8_modrm(uint reg_field, uint rm)
{
    return (reg_field >= 8u && reg_field < 16u) || (rm >= 4u && rm < 16u) ? 1u : 0u;
}

uint packed_reg_a(uint packed)
{
    return packed_u8_at(packed, 0u);
}

uint packed_reg_b(uint packed)
{
    return packed_u8_at(packed, 1u);
}

uint mov_r32_imm32_size(uint dst)
{
    return valid_reg(dst) ? 5u + rex_for_opcode_reg(dst) : 0u;
}

uint xor_r32_self_size(uint reg)
{
    return valid_reg(reg) ? 2u + rex_for_modrm(reg, reg) : 0u;
}

bool signed_i8_immediate(uint imm)
{
    return imm <= 127u || imm >= 0xffffff80u;
}

uint mov_r32_imm_compact_size(uint dst, uint imm)
{
    if (!valid_reg(dst))
        return 0u;
    if (imm == 0u)
        return xor_r32_self_size(dst);
    if (dst != X86_REG_ESP && signed_i8_immediate(imm))
        return 2u + push_pop_reg_size(dst);
    return mov_r32_imm32_size(dst);
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

uint cmp_r32_r32_size(uint left, uint right)
{
    return valid_reg(left) && valid_reg(right) ? 2u + rex_for_modrm(right, left) : 0u;
}

uint local_slot_disp(uint slot)
{
    return (slot + 3u) * 4u;
}

bool valid_local_slot(uint slot)
{
    return slot < MAX_X86_LOCAL_SLOTS;
}

uint cmp_local_r32_size(uint slot, uint reg)
{
    if (!valid_reg(reg) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    return (disp <= 127u ? 4u : 7u) + rex_for_modrm(reg, 4u);
}

uint branch_zero_size(uint cond)
{
    return valid_reg(cond) ? 2u + rex_for_modrm(cond, cond) + 6u : 0u;
}

uint local_mem_r32_size(uint reg, uint slot)
{
    if (!valid_reg(reg) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    return (disp <= 127u ? 4u : 7u) + rex_for_modrm(reg, 4u);
}

bool valid_index_reg(uint reg)
{
    return valid_reg(reg) && (reg & 7u) != 4u;
}

uint local_index_mem_r32_size(uint dst, uint slot, uint index)
{
    if (!valid_reg(dst) || !valid_index_reg(index) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    return (disp <= 127u ? 4u : 7u) + rex_for_sib(dst, index, 4u);
}

uint param_index_mem_r32_size(uint dst, uint base, uint index)
{
    return valid_reg(dst) && valid_reg(base) && valid_index_reg(index) && (base & 7u) != 4u
               ? 4u + rex_for_sib(dst, index, base)
               : 0u;
}

uint ptr_slot_mem_r32_size(uint reg, uint base, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(reg) && valid_reg(base) && disp <= 127u
               ? 3u + rex_for_modrm(reg, base)
               : 0u;
}

uint ptr_slot_zero_size(uint base, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(base) && disp <= 127u
               ? 4u + rex_for_modrm(4u, base)
               : 0u;
}

uint ptr_slot_imm32_size(uint base, uint ordinal, uint imm)
{
    uint disp = ordinal * 4u;
    if (imm == 0u)
        return ptr_slot_zero_size(base, ordinal);
    return valid_reg(base) && disp <= 127u
               ? 7u + rex_for_modrm(0u, base)
               : 0u;
}

uint cmp_ptr_slot_imm32_size(uint base, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(base) && disp <= 127u
               ? 7u + rex_for_modrm(7u, base)
               : 0u;
}

uint lea_arg_local_ptr_size(uint target, uint slot, uint stack_adjust)
{
    if (!valid_reg(target) || !valid_local_slot(slot))
        return 0u;
    uint disp = stack_adjust + local_slot_disp(slot);
    return disp <= 127u ? 5u : 8u;
}

uint mov_r64_r64_size(uint dst, uint src)
{
    return valid_reg(dst) && valid_reg(src) ? 3u : 0u;
}

uint local_zero_size(uint slot)
{
    if (!valid_local_slot(slot))
        return 0u;
    return local_slot_disp(slot) <= 127u ? 5u : 8u;
}

uint local_imm32_size(uint slot, uint imm)
{
    if (!valid_local_slot(slot))
        return 0u;
    if (imm == 0u)
        return local_zero_size(slot);
    return local_slot_disp(slot) <= 127u ? 8u : 11u;
}

uint cmp_local_imm_size(uint slot, uint imm)
{
    if (!valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    if (signed_i8_immediate(imm))
        return disp <= 127u ? 5u : 8u;
    return disp <= 127u ? 8u : 11u;
}

uint cmp_ptr_slot_imm_size(uint base, uint ordinal, uint imm)
{
    uint disp = ordinal * 4u;
    if (!valid_reg(base) || disp > 127u)
        return 0u;
    return (signed_i8_immediate(imm) ? 4u : 7u) + rex_for_modrm(7u, base);
}

uint for_array_branch_size(uint index_slot, uint len)
{
    uint cmp_size = cmp_local_imm_size(index_slot, len);
    return cmp_size == 0u ? 0u : cmp_size + 6u;
}

uint match_tag_branch_size(uint source_kind, uint tag, uint payload)
{
    uint cmp_size = 0u;
    if (source_kind == X86_AGG_SOURCE_LOCAL)
        cmp_size = cmp_local_imm_size(payload, tag);
    else if (source_kind == X86_AGG_SOURCE_PARAM)
        cmp_size = cmp_ptr_slot_imm_size(payload, 0u, tag);
    return cmp_size == 0u ? 0u : cmp_size + 6u;
}

uint for_array_load_size(uint array_base_slot, uint index_slot, uint value_slot)
{
    uint load_index = local_mem_r32_size(X86_REG_R11D, index_slot);
    uint load_value = local_index_mem_r32_size(X86_REG_R11D, array_base_slot, X86_REG_R11D);
    uint store_value = local_mem_r32_size(X86_REG_R11D, value_slot);
    return load_index != 0u && load_value != 0u && store_value != 0u
               ? load_index + load_value + store_value
               : 0u;
}

uint for_array_inc_jmp_size(uint index_slot)
{
    if (!valid_local_slot(index_slot))
        return 0u;
    return (local_slot_disp(index_slot) <= 127u ? 5u : 8u) + 5u;
}

uint copy_local_r32_size(uint dst_slot, uint src_slot)
{
    uint load_size = local_mem_r32_size(X86_REG_R11D, src_slot);
    uint store_size = local_mem_r32_size(X86_REG_R11D, dst_slot);
    return load_size != 0u && store_size != 0u ? load_size + store_size : 0u;
}

uint for_interval_branch_size(uint index_slot, uint end_slot)
{
    uint load_end = local_mem_r32_size(X86_REG_R11D, end_slot);
    uint cmp_size = cmp_local_r32_size(index_slot, X86_REG_R11D);
    return load_end != 0u && cmp_size != 0u
               ? load_end + cmp_size + 6u
               : 0u;
}

uint return_size(uint src)
{
    if (!valid_reg(src))
        return 0u;
    uint move_size = src == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, src);
    return move_size + mov_r32_imm_compact_size(X86_REG_EAX, 60u) + 2u;
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

bool call_save_mask_has_slot(uint save_mask, uint slot)
{
    return ((save_mask >> slot) & 1u) != 0u;
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

uint call_save_restore_size(uint save_mask)
{
    uint size = 0u;
    [unroll]
    for (uint slot = 0u; slot < 8u; slot += 1u)
        if (call_save_mask_has_slot(save_mask, slot))
            size += push_pop_reg_size(call_saved_reg_for_slot(slot));
    return size;
}

uint call_save_stack_size(uint save_mask)
{
    uint size = 0u;
    [unroll]
    for (uint slot = 0u; slot < 8u; slot += 1u)
        if (call_save_mask_has_slot(save_mask, slot))
            size += 8u;
    return size;
}

uint call_frame_size(uint save_stack)
{
    uint local_slots = x86_decl_layout_status[3u];
    uint bytes = max((local_slots + 3u) * 4u, MIN_X86_STACK_FRAME_BYTES);
    bytes = (bytes + 15u) & 0xfffffff0u;
    return (save_stack & 8u) != 0u ? bytes + 8u : bytes;
}

uint stack_frame_adjust_size(uint frame_size)
{
    if (frame_size == 0u)
        return 0u;
    return frame_size <= 127u ? 4u : 7u;
}

bool call_saved_reg_slot(uint reg, out uint slot)
{
    slot = 0xffffffffu;
    [unroll]
    for (uint candidate = 0u; candidate < 8u; candidate += 1u)
    {
        if (call_saved_reg_for_slot(candidate) == reg)
        {
            slot = candidate;
            return true;
        }
    }
    return false;
}

uint load_saved_call_reg_r32_size(uint dst, uint src, uint save_mask)
{
    uint slot = 0xffffffffu;
    if (!valid_reg(dst) || !call_saved_reg_slot(src, slot) ||
        !call_save_mask_has_slot(save_mask, slot))
        return 0u;
    return 4u + rex_for_modrm(dst, 4u);
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

uint exit_zero_size()
{
    return mov_r32_imm_compact_size(X86_REG_EDI, 0u) +
           mov_r32_imm_compact_size(X86_REG_EAX, 60u) +
           2u;
}

uint mixed_target_reg(uint ordinal, bool aggregate_return)
{
    uint shifted = ordinal + (aggregate_return ? 1u : 0u);
    if (shifted == 0u) return X86_REG_EDI;
    if (shifted == 1u) return X86_REG_ESI;
    if (shifted == 2u) return X86_REG_EDX;
    if (shifted == 3u) return X86_REG_ECX;
    if (shifted == 4u) return X86_REG_R8D;
    if (shifted == 5u) return X86_REG_R9D;
    return 0xffffffffu;
}

uint selected_mixed_arg_kind(uint info, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u2_at_offset(info, 24u, ordinal);
    return 0u;
}

uint selected_mixed_arg_payload(uint packed, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u8_at(packed, ordinal);
    return 0xffffffffu;
}

uint mixed_arg_move_size(uint target, uint kind, uint payload, uint save_mask, uint save_size)
{
    if (kind == X86_ARG_SCALAR)
    {
        if (!valid_reg(payload))
            return 0u;
        if (payload == target)
            return 0u;
        uint saved_load_size = load_saved_call_reg_r32_size(target, payload, save_mask);
        return saved_load_size != 0u ? saved_load_size : mov_r32_r32_size(target, payload);
    }
    if (kind == X86_ARG_LOCAL_PTR)
        return lea_arg_local_ptr_size(target, payload, save_size);
    if (kind == X86_ARG_PARAM_PTR)
        return payload == target ? 0u : mov_r64_r64_size(target, payload);
    return 0u;
}

uint call_mixed_size(uint target, uint info, uint packed, uint save_mask)
{
    bool aggregate_return = (info & 1u) != 0u;
    uint dest = packed_u8_at(info, 1u);
    uint arg_count = packed_u8_at(info, 2u);
    if (arg_count > 4u || (aggregate_return && !valid_local_slot(dest)) ||
        (!aggregate_return && !valid_reg(dest)))
        return 0u;

    uint save_size = call_save_restore_size(save_mask);
    uint save_stack = call_save_stack_size(save_mask);
    uint size = save_size;
    if (aggregate_return)
        size += lea_arg_local_ptr_size(X86_REG_EDI, dest, save_stack);

    [unroll]
    for (uint ordinal = 0u; ordinal < 4u; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;
        uint target_reg = mixed_target_reg(ordinal, aggregate_return);
        if (!valid_reg(target_reg))
            return 0u;
        uint payload = selected_mixed_arg_payload(packed, ordinal);
        uint kind = selected_mixed_arg_kind(info, ordinal);
        uint move_size = mixed_arg_move_size(target_reg, kind, payload, save_mask, save_stack);
        if (move_size == 0u &&
            !(kind == X86_ARG_SCALAR && payload == target_reg) &&
            !(kind == X86_ARG_PARAM_PTR && payload == target_reg))
            return 0u;
        size += move_size;
    }

    uint frame_adjust_size = stack_frame_adjust_size(call_frame_size(save_stack));
    size += frame_adjust_size + 5u + frame_adjust_size + save_size;
    if (!aggregate_return && dest != X86_REG_EAX)
        size += mov_r32_r32_size(dest, X86_REG_EAX);
    return size;
}

uint copy_agg_ret_size(uint source_kind, uint payload, uint ordinal)
{
    if (source_kind == X86_AGG_SOURCE_LOCAL)
    {
        uint load_size = local_mem_r32_size(X86_REG_R11D, payload + ordinal);
        uint store_size = ptr_slot_mem_r32_size(X86_REG_R11D, X86_REG_EDI, ordinal);
        return load_size != 0u && store_size != 0u ? load_size + store_size : 0u;
    }
    if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint load_size = ptr_slot_mem_r32_size(X86_REG_R11D, payload, ordinal);
        uint store_size = ptr_slot_mem_r32_size(X86_REG_R11D, X86_REG_EDI, ordinal);
        return load_size != 0u && store_size != 0u ? load_size + store_size : 0u;
    }
    return 0u;
}

uint inst_kind_tag(uint inst_i)
{
    return x86_inst_kind[inst_i] & 0xffu;
}

uint inst_call_save_mask(uint inst_i)
{
    return (x86_inst_kind[inst_i] >> 8u) & 0xffu;
}

uint byte_size_for_inst(uint inst_i)
{
    uint kind = inst_kind_tag(inst_i);
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
    if (kind == X86_INST_V_MOV_R32_IMM32) return mov_r32_imm_compact_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_MOV_R32_R32) return mov_r32_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_UNARY_R32) return unary_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_BINARY_R32_R32) return binary_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_COMPARE_R32_R32) return compare_size(x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_RETURN_R32) return return_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_BRANCH_ZERO) return branch_zero_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_JMP) return 5u;
    if (kind == X86_INST_V_PARAM_R32) return mov_r32_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_RETURN_FUNC_R32) return return_func_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_PRINT_I32) return print_i32_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_LOAD_LOCAL_R32) return local_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_STORE_LOCAL_R32) return local_mem_r32_size(x86_inst_arg1[inst_i], x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_LOAD_LOCAL_INDEX_R32) return local_index_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_STORE_LOCAL_IMM32) return local_imm32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_FOR_ARRAY_BRANCH) return for_array_branch_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_FOR_ARRAY_LOAD) return for_array_load_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_FOR_ARRAY_INC_JMP) return for_array_inc_jmp_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_FOR_INTERVAL_BRANCH) return for_interval_branch_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_COPY_LOCAL_R32) return copy_local_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_CALL_MIXED_DIRECT) return call_mixed_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], inst_call_save_mask(inst_i));
    if (kind == X86_INST_V_LOAD_PARAM_INDEX_R32) return param_index_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_STORE_RET_PTR_R32) return ptr_slot_mem_r32_size(x86_inst_arg0[inst_i], X86_REG_EDI, x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_COPY_AGG_RET) return copy_agg_ret_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_STORE_RET_PTR_IMM32) return ptr_slot_imm32_size(X86_REG_EDI, x86_inst_arg1[inst_i], x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_LOAD_PTR_SLOT_R32) return ptr_slot_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_MATCH_TAG_BRANCH) return match_tag_branch_size(unpack_u16_pair_low(x86_inst_arg0[inst_i]), unpack_u16_pair_high(x86_inst_arg0[inst_i]), x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_ENTRY_STACK_JMP) return stack_frame_adjust_size(x86_inst_arg1[inst_i]) + 5u;
    if (kind == X86_INST_V_EXIT_ZERO) return exit_zero_size();
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint inst_i = linear_dispatch_id(tid);
    bool select_ok = select_status[0u] == X86_SELECT_OK &&
                     select_status[3u] <= gParams.inst_capacity;
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
    if (size == 0u && x86_inst_kind[inst_i] != 0u)
        publish_stage_error_min_detail4(size_status, X86_ERR_INST_SIZE, inst_i);
}
