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
static const uint INVALID = 0xffffffffu;
static const uint X86_ERR_INST_SIZE = 6u;
static const uint X86_MAX_ENCODED_INST_BYTES = 256u;

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
static const uint X86_INST_V_CALL_MIXED_EXTERNAL = 124u;
static const uint X86_INST_V_LOAD_PARAM_INDEX_R32 = 72u;
static const uint X86_INST_V_STORE_RET_PTR_R32 = 73u;
static const uint X86_INST_V_COPY_AGG_RET = 74u;
static const uint X86_INST_V_STORE_RET_PTR_IMM32 = 75u;
static const uint X86_INST_V_LOAD_PTR_SLOT_R32 = 76u;
static const uint X86_INST_V_MATCH_TAG_BRANCH = 77u;
static const uint X86_INST_V_FOR_INTERVAL_BRANCH = 78u;
static const uint X86_INST_V_COPY_LOCAL_R32 = 79u;
static const uint X86_INST_V_STORE_LOCAL_INDEX_R32 = 80u;
static const uint X86_INST_V_FOR_PARAM_ARRAY_LOAD = 81u;
static const uint X86_INST_V_STORE_PARAM_INDEX_R32 = 82u;
static const uint X86_INST_V_STORE_LOCAL_RODATA_PTR = 83u;
static const uint X86_INST_V_HOST_TEXT_WRITE = 84u;
static const uint X86_INST_V_HOST_OPEN_WRITE_PATH = 85u;
static const uint X86_INST_V_HOST_WRITE_I32 = 86u;
static const uint X86_INST_V_HOST_WRITE_BYTE = 87u;
static const uint X86_INST_V_HOST_WRITE_NEWLINE = 88u;
static const uint X86_INST_V_HOST_OPEN_READ_PATH = 89u;
static const uint X86_INST_V_HOST_READ_I32 = 90u;
static const uint X86_INST_V_HOST_PROCESS_EXIT = 91u;
static const uint X86_INST_V_HOST_SECURE_U32 = 92u;
static const uint X86_INST_V_HOST_ALLOC = 93u;
static const uint X86_INST_V_HOST_DEALLOC = 94u;
static const uint X86_INST_V_HOST_ARGC = 95u;
static const uint X86_INST_V_HOST_ARG_LEN = 96u;
static const uint X86_INST_V_HOST_ARG_READ = 97u;
static const uint X86_INST_V_HOST_UNIX_SECONDS = 98u;
static const uint X86_INST_V_HOST_CURRENT_DIR_READ = 99u;
static const uint X86_INST_V_HOST_VAR_COUNT = 100u;
static const uint X86_INST_V_HOST_VAR_KEY_LEN = 101u;
static const uint X86_INST_V_HOST_VAR_KEY_READ = 102u;
static const uint X86_INST_V_HOST_VAR_LEN = 103u;
static const uint X86_INST_V_HOST_VAR_READ = 104u;
static const uint X86_INST_V_HOST_CLOSE_FILE = 105u;
static const uint X86_INST_V_HOST_FS_READ = 106u;
static const uint X86_INST_V_HOST_FS_WRITE = 107u;
static const uint X86_INST_V_HOST_FS_OPEN_READ = 108u;
static const uint X86_INST_V_HOST_FS_OPEN_WRITE = 109u;
static const uint X86_INST_V_HOST_FS_OPEN_APPEND = 110u;
static const uint X86_INST_V_HOST_STDIN_READ = 111u;
static const uint X86_INST_V_HOST_STDOUT_WRITE = 112u;
static const uint X86_INST_V_HOST_STDERR_WRITE = 113u;
static const uint X86_INST_V_HOST_FILL_SECURE_BYTES = 114u;
static const uint X86_INST_V_HOST_FS_REMOVE_FILE = 115u;
static const uint X86_INST_V_HOST_FS_CREATE_DIR = 116u;
static const uint X86_INST_V_HOST_FS_REMOVE_DIR = 117u;
static const uint X86_INST_V_HOST_FS_RENAME = 118u;
static const uint X86_INST_V_HOST_TIME_MONOTONIC_READ = 119u;
static const uint X86_INST_V_HOST_TIME_SYSTEM_READ = 120u;
static const uint X86_INST_V_HOST_TIME_SLEEP_MS_I32 = 121u;
static const uint X86_INST_V_HOST_REALLOC = 122u;
static const uint X86_INST_V_HOST_ALLOC_FAILED = 123u;
static const uint HOST_PATH_BUFFER_BYTES = 4096u;
static const uint HOST_PATH_MAX_BYTES = 4095u;
static const uint X86_ARG_SCALAR = 1u;
static const uint X86_ARG_LOCAL_PTR = 2u;
static const uint X86_ARG_PARAM_PTR = 3u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;
static const uint X86_AGG_SOURCE_REG = 3u;
static const uint X86_AGG_RETURN_DEST_RET_PTR = 0xffu;
// Keep local-slot displacements within x86 signed disp32 while allowing large
// generated functions to exceed the old 16-bit-era guard.
static const uint MAX_X86_LOCAL_SLOTS = 1000000u;
static const uint MIN_X86_STACK_FRAME_BYTES = 16u;

static const uint X86_OP_NEG_I32 = 1u;
static const uint X86_OP_NOT_BOOL = 2u;
static const uint X86_OP_NEG_F32 = 3u;
static const uint X86_OP_I32_TO_F32 = 4u;
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
static const uint X86_OP_MOD_U32 = 13u;
static const uint X86_OP_DIV_U32 = 14u;
static const uint X86_OP_SHR_U32 = 15u;
static const uint X86_OP_ADD_F32 = 16u;
static const uint X86_OP_SUB_F32 = 17u;
static const uint X86_OP_MUL_F32 = 18u;
static const uint X86_OP_DIV_F32 = 19u;
static const uint I32_MIN = 0x80000000u;
static const uint I32_NEG_ONE = 0xffffffffu;
static const uint X86_CMP_FLOAT_FLAG = 0x40u;
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
static const uint X86_REG_R15D = 15u;

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
    if (op == X86_OP_NEG_F32)
        return move_size + 6u + rex_for_modrm(6u, dst);
    if (op == X86_OP_I32_TO_F32)
        return 4u + rex_for_modrm(0u, src) +
               4u + rex_for_modrm(0u, dst);
    return 0u;
}

bool f32_binary_op(uint op)
{
    return op == X86_OP_ADD_F32 ||
           op == X86_OP_SUB_F32 ||
           op == X86_OP_MUL_F32 ||
           op == X86_OP_DIV_F32;
}

uint movd_xmm_r32_size(uint src)
{
    return valid_reg(src) ? 4u + rex_for_modrm(0u, src) : 0u;
}

uint movd_r32_xmm_size(uint dst)
{
    return valid_reg(dst) ? 4u + rex_for_modrm(0u, dst) : 0u;
}

uint f32_binary_size(uint op, uint dst, uint left, uint right)
{
    if (!f32_binary_op(op) || !valid_reg(dst) || !valid_reg(left) || !valid_reg(right))
        return 0u;
    return movd_xmm_r32_size(left) +
           movd_xmm_r32_size(right) +
           4u +
           movd_r32_xmm_size(dst);
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
    if (op == X86_OP_SHL_I32 || op == X86_OP_SHR_I32 || op == X86_OP_SHR_U32)
        return (right == X86_REG_ECX ? 0u : mov_r32_r32_size(X86_REG_ECX, right)) +
               2u + rex_for_modrm(
                   op == X86_OP_SHL_I32 ? 4u
                 : op == X86_OP_SHR_U32 ? 5u
                 : 7u,
                   dst);
    return 0u;
}

uint divmod_size(uint op, uint dst, uint left, uint right)
{
    bool signed_op = op == X86_OP_DIV_I32 || op == X86_OP_MOD_I32;
    bool unsigned_op = op == X86_OP_DIV_U32 || op == X86_OP_MOD_U32;
    if (!signed_op && !unsigned_op)
        return 0u;
    if (!valid_reg(dst) || !valid_reg(left) || !valid_reg(right))
        return 0u;

    uint size = 0u;
    if (right != X86_REG_ECX)
        size += mov_r32_r32_size(X86_REG_ECX, right);
    if (left != X86_REG_EAX)
        size += mov_r32_r32_size(X86_REG_EAX, left);
    size += unsigned_op ? xor_r32_self_size(X86_REG_EDX) : 1u;
    size += 2u + rex_for_modrm(unsigned_op ? 6u : 7u, X86_REG_ECX);
    uint result = (op == X86_OP_MOD_I32 || op == X86_OP_MOD_U32) ? X86_REG_EDX : X86_REG_EAX;
    if (dst != result)
        size += mov_r32_r32_size(dst, result);
    return size;
}

uint zero_divisor_check_size(uint divisor)
{
    if (!valid_reg(divisor))
        return 0u;
    uint cmp_size = cmp_r32_imm_size(divisor, 0u);
    uint trap_size = exit_code_size(103u);
    return cmp_size != 0u && trap_size != 0u ? cmp_size + 6u + trap_size : 0u;
}

uint signed_div_overflow_check_size(uint left, uint right)
{
    if (!valid_reg(left) || !valid_reg(right))
        return 0u;
    uint right_cmp_size = cmp_r32_imm_size(right, I32_NEG_ONE);
    uint left_cmp_size = cmp_r32_imm_size(left, I32_MIN);
    uint trap_size = exit_code_size(104u);
    return right_cmp_size != 0u && left_cmp_size != 0u && trap_size != 0u
               ? right_cmp_size + 6u + left_cmp_size + 6u + trap_size
               : 0u;
}

uint divmod_trap_check_size(uint left, uint right)
{
    uint zero_check = zero_divisor_check_size(right);
    uint overflow_check = signed_div_overflow_check_size(left, right);
    return zero_check != 0u && overflow_check != 0u ? zero_check + overflow_check : 0u;
}

uint binary_size(uint op, uint dst, uint packed)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    if (!valid_reg(dst) || !valid_reg(left) || !valid_reg(right))
        return 0u;
    if (op == X86_OP_DIV_I32 || op == X86_OP_MOD_I32 ||
        op == X86_OP_DIV_U32 || op == X86_OP_MOD_U32)
    {
        bool unsigned_op = op == X86_OP_DIV_U32 || op == X86_OP_MOD_U32;
        uint check_size = unsigned_op
                              ? zero_divisor_check_size(right)
                              : divmod_trap_check_size(left, right);
        uint op_size = divmod_size(op, dst, left, right);
        return check_size != 0u && op_size != 0u ? check_size + op_size : 0u;
    }
    if (op == X86_OP_SHL_I32 || op == X86_OP_SHR_I32 || op == X86_OP_SHR_U32)
    {
        uint check_size = shift_count_check_size(right);
        uint move_size = dst == left ? 0u : mov_r32_r32_size(dst, left);
        uint op_size = binary_alu_size(op, dst, right);
        return check_size != 0u && op_size != 0u ? check_size + move_size + op_size : 0u;
    }
    if (f32_binary_op(op))
        return f32_binary_size(op, dst, left, right);

    uint move_size = dst == left ? 0u : mov_r32_r32_size(dst, left);
    uint op_size = binary_alu_size(op, dst, right);
    return op_size == 0u ? 0u : move_size + op_size;
}

uint compare_size(uint op, uint dst, uint packed)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    if (!valid_reg(dst) || !valid_reg(left) || !valid_reg(right))
        return 0u;
    if ((op & X86_CMP_FLOAT_FLAG) != 0u)
        return movd_xmm_r32_size(left) +
               movd_xmm_r32_size(right) +
               3u +
               3u + rex_for_low8_modrm(0u, dst) +
               3u + rex_for_low8_modrm(dst, dst);
    return 2u + rex_for_modrm(right, left) +
           3u + rex_for_low8_modrm(0u, dst) +
           3u + rex_for_low8_modrm(dst, dst);
}

uint cmp_r32_r32_size(uint left, uint right)
{
    return valid_reg(left) && valid_reg(right) ? 2u + rex_for_modrm(right, left) : 0u;
}

uint cmp_r32_imm_size(uint reg, uint imm)
{
    return valid_reg(reg)
               ? (signed_i8_immediate(imm) ? 3u : 6u) + rex_for_modrm(7u, reg)
               : 0u;
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

uint local_mem_r32_adjusted_size(uint reg, uint slot, uint stack_adjust)
{
    if (!valid_reg(reg) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot) + stack_adjust;
    return (disp <= 127u ? 4u : 7u) + rex_for_modrm(reg, 4u);
}

bool valid_index_reg(uint reg)
{
    return valid_reg(reg) && (reg & 7u) != 4u;
}

uint packed_index_reg(uint packed)
{
    return packed & 0xffu;
}

uint packed_index_width(uint packed)
{
    return packed >> 8u;
}

uint param_aggregate_payload_base(uint payload)
{
    return unpack_u16_pair_low(payload);
}

uint param_aggregate_payload_ordinal(uint payload)
{
    return unpack_u16_pair_high(payload);
}

uint exit_code_size(uint code)
{
    return mov_r32_imm_compact_size(X86_REG_EDI, code) +
           mov_r32_imm_compact_size(X86_REG_EAX, 60u) +
           2u;
}

uint unsigned_lt_trap_check_size(uint reg, uint limit, uint exit_code)
{
    if (!valid_reg(reg))
        return 0u;
    uint cmp_size = cmp_r32_imm_size(reg, limit);
    uint trap_size = exit_code_size(exit_code);
    return cmp_size != 0u && trap_size != 0u ? cmp_size + 6u + trap_size : 0u;
}

uint index_bounds_check_size(uint index, uint width)
{
    if (!valid_index_reg(index) || width == 0u)
        return 0u;
    return unsigned_lt_trap_check_size(index, width, 101u);
}

uint shift_count_check_size(uint count)
{
    return unsigned_lt_trap_check_size(count, 32u, 102u);
}

uint local_index_mem_r32_size(uint dst, uint slot, uint index)
{
    if (!valid_reg(dst) || !valid_index_reg(index) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    return (disp <= 127u ? 4u : 7u) + rex_for_sib(dst, index, 4u);
}

uint checked_local_index_mem_r32_size(uint dst, uint slot, uint packed)
{
    uint index = packed_index_reg(packed);
    uint width = packed_index_width(packed);
    uint check_size = index_bounds_check_size(index, width);
    uint access_size = local_index_mem_r32_size(dst, slot, index);
    return check_size != 0u && access_size != 0u ? check_size + access_size : 0u;
}

uint param_index_mem_r32_size(uint dst, uint base, uint index)
{
    return valid_reg(dst) && valid_reg(base) && valid_index_reg(index) && (base & 7u) != 4u
               ? 4u + rex_for_sib(dst, index, base)
               : 0u;
}

uint param_index_slot_mem_r32_size(uint dst, uint base, uint index, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(dst) && valid_reg(base) && valid_index_reg(index) &&
                   (base & 7u) != 4u
               ? (disp <= 127u ? 4u : 7u) + rex_for_sib(dst, index, base)
               : 0u;
}

uint checked_param_index_mem_r32_size(uint dst, uint base, uint packed)
{
    uint payload_base = param_aggregate_payload_base(base);
    uint payload_ordinal = param_aggregate_payload_ordinal(base);
    uint index = packed_index_reg(packed);
    uint width = packed_index_width(packed);
    uint check_size = index_bounds_check_size(index, width);
    uint access_size = param_index_slot_mem_r32_size(dst, payload_base, index, payload_ordinal);
    return check_size != 0u && access_size != 0u ? check_size + access_size : 0u;
}

uint ptr_slot_mem_r32_size(uint reg, uint base, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(reg) && valid_reg(base)
               ? (disp <= 127u ? 3u : 6u) + rex_for_modrm(reg, base)
               : 0u;
}

uint ptr_slot_zero_size(uint base, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(base)
               ? (disp <= 127u ? 4u : 7u) + rex_for_modrm(4u, base)
               : 0u;
}

uint ptr_slot_imm32_size(uint base, uint ordinal, uint imm)
{
    uint disp = ordinal * 4u;
    if (imm == 0u)
        return ptr_slot_zero_size(base, ordinal);
    return valid_reg(base)
               ? (disp <= 127u ? 7u : 10u) + rex_for_modrm(0u, base)
               : 0u;
}

uint cmp_ptr_slot_imm32_size(uint base, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(base)
               ? (disp <= 127u ? 7u : 10u) + rex_for_modrm(7u, base)
               : 0u;
}

uint lea_arg_local_ptr_size(uint target, uint slot, uint stack_adjust)
{
    if (!valid_reg(target) || !valid_local_slot(slot))
        return 0u;
    uint disp = stack_adjust + local_slot_disp(slot);
    return disp <= 127u ? 5u : 8u;
}

uint lea_arg_param_ptr_size(uint target, uint payload)
{
    uint base = param_aggregate_payload_base(payload);
    uint ordinal = param_aggregate_payload_ordinal(payload);
    uint disp = ordinal * 4u;
    if (!valid_reg(target) || !valid_reg(base) || (base & 7u) == 4u)
        return 0u;
    return disp <= 127u ? 4u : 7u;
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
    if (!valid_reg(base))
        return 0u;
    if (signed_i8_immediate(imm))
        return (disp <= 127u ? 4u : 7u) + rex_for_modrm(7u, base);
    return (disp <= 127u ? 7u : 10u) + rex_for_modrm(7u, base);
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
        cmp_size = cmp_ptr_slot_imm_size(
            param_aggregate_payload_base(payload),
            param_aggregate_payload_ordinal(payload),
            tag);
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

uint for_param_array_load_size(uint packed_base, uint index_slot, uint value_slot)
{
    uint array_base_reg = unpack_u16_pair_low(packed_base);
    uint ordinal = unpack_u16_pair_high(packed_base);
    uint load_index = local_mem_r32_size(X86_REG_R11D, index_slot);
    uint load_value = param_index_slot_mem_r32_size(X86_REG_R11D, array_base_reg, X86_REG_R11D, ordinal);
    uint store_value = local_mem_r32_size(X86_REG_R11D, value_slot);
    return load_index != 0u && load_value != 0u && store_value != 0u
               ? load_index + load_value + store_value
               : 0u;
}

uint for_array_inc_jmp_size(uint index_slot, uint stride)
{
    if (!valid_local_slot(index_slot))
        return 0u;
    if (stride == 0u)
        stride = 1u;
    if (stride > 127u)
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
    uint active = save_mask & 0xffu;
    uint high = active & 0xf0u;
    return countbits(active) + countbits(high);
}

uint call_save_stack_size(uint save_mask)
{
    return countbits(save_mask & 0xffu) * 8u;
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

uint process_stack_save_size()
{
    return 3u;
}

bool call_saved_reg_slot(uint reg, out uint slot)
{
    slot = 0xffffffffu;
    if (reg == X86_REG_ECX) { slot = 0u; return true; }
    if (reg == X86_REG_EDX) { slot = 1u; return true; }
    if (reg == X86_REG_ESI) { slot = 2u; return true; }
    if (reg == X86_REG_EDI) { slot = 3u; return true; }
    if (reg == X86_REG_R8D) { slot = 4u; return true; }
    if (reg == X86_REG_R9D) { slot = 5u; return true; }
    if (reg == X86_REG_R10D) { slot = 6u; return true; }
    if (reg == X86_REG_R11D) { slot = 7u; return true; }
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

uint load_saved_call_reg_r64_size(uint dst, uint src, uint save_mask)
{
    uint slot = 0xffffffffu;
    if (!valid_reg(dst) || !call_saved_reg_slot(src, slot) ||
        !call_save_mask_has_slot(save_mask, slot))
        return 0u;
    return 5u;
}

uint print_save_restore_size()
{
    return 13u;
}

uint print_save_stack_size()
{
    return 72u;
}

bool print_saved_reg_slot(uint reg, out uint slot)
{
    slot = 0xffffffffu;
    if (reg == X86_REG_EAX) { slot = 0u; return true; }
    if (reg == X86_REG_ECX) { slot = 1u; return true; }
    if (reg == X86_REG_EDX) { slot = 2u; return true; }
    if (reg == X86_REG_ESI) { slot = 3u; return true; }
    if (reg == X86_REG_EDI) { slot = 4u; return true; }
    if (reg == X86_REG_R8D) { slot = 5u; return true; }
    if (reg == X86_REG_R9D) { slot = 6u; return true; }
    if (reg == X86_REG_R10D) { slot = 7u; return true; }
    if (reg == X86_REG_R11D) { slot = 8u; return true; }
    return false;
}

uint load_print_saved_reg_r32_size(uint dst, uint src)
{
    uint slot = 0xffffffffu;
    return valid_reg(dst) && print_saved_reg_slot(src, slot)
               ? 4u + rex_for_modrm(dst, 4u)
               : 0u;
}

uint host_arg_source_r32_size(uint dst, uint src)
{
    uint slot = 0xffffffffu;
    if (print_saved_reg_slot(src, slot))
        return load_print_saved_reg_r32_size(dst, src);
    return valid_reg(dst) && valid_reg(src) ? mov_r32_r32_size(dst, src) : 0u;
}

uint print_i32_size(uint src)
{
    if (!valid_reg(src))
        return 0u;
    uint src_move = src == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, src);
    return print_save_restore_size() + 92u + src_move + print_save_restore_size();
}

uint host_text_write_size(uint packed, uint text_payload, uint text_len)
{
    uint handle = packed_reg_a(packed);
    uint dst = packed_reg_b(packed);
    if (!valid_reg(handle) || !valid_reg(dst))
        return 0u;
    uint handle_move = handle == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, handle);
    uint save_stack = print_save_stack_size();
    uint text_setup = 0u;
    if (text_len == INVALID)
    {
        if (!valid_local_slot(text_payload) || !valid_local_slot(text_payload + 1u))
            return 0u;
        text_setup = local_mem_r32_adjusted_size(X86_REG_ESI, text_payload, save_stack) +
                     local_mem_r32_adjusted_size(X86_REG_EDX, text_payload + 1u, save_stack);
    }
    else
    {
        text_setup = mov_r32_imm32_size(X86_REG_ESI) +
                     mov_r32_imm32_size(X86_REG_EDX);
    }
    return print_save_restore_size() + handle_move + text_setup +
           mov_r32_imm32_size(X86_REG_EAX) + 2u +
           print_save_restore_size() + xor_r32_self_size(dst);
}

uint host_open_path_source_size(uint path_payload, uint source_kind, uint save_stack)
{
    if (source_kind == X86_AGG_SOURCE_LOCAL)
        return local_mem_r32_adjusted_size(X86_REG_EDI, path_payload, save_stack);
    if (source_kind == X86_AGG_SOURCE_PARAM)
        return ptr_slot_mem_r32_size(
            X86_REG_EDI,
            param_aggregate_payload_base(path_payload),
            param_aggregate_payload_ordinal(path_payload));
    return mov_r32_imm32_size(X86_REG_EDI);
}

uint host_open_path_size(uint dst, uint path_payload, uint source_kind)
{
    if (!valid_reg(dst))
        return 0u;
    uint save_stack = print_save_stack_size();
    uint path_setup = host_open_path_source_size(path_payload, source_kind, save_stack);
    if (path_setup == 0u)
        return 0u;
    return print_save_restore_size() +
           path_setup +
           mov_r32_imm32_size(X86_REG_ESI) +
           mov_r32_imm32_size(X86_REG_EDX) +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u + 4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint lea_r64_rsp_size(uint dst, uint disp)
{
    return valid_reg(dst) ? (disp <= 127u ? 5u : 8u) : 0u;
}

uint add_r32_imm8_size(uint reg)
{
    return valid_reg(reg) ? 3u + rex_for_modrm(0u, reg) : 0u;
}

uint host_path_open_finish_size(uint dst)
{
    return 7u +
           7u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_path_buffer_copy_size()
{
    uint start_size = lea_r64_rsp_size(X86_REG_EDI, 0u) +
                      xor_r32_self_size(X86_REG_ECX);
    uint cmp_size = cmp_r32_r32_size(X86_REG_ECX, X86_REG_R9D);
    uint step_size = add_r32_imm8_size(X86_REG_ECX);
    if (start_size == 0u || cmp_size == 0u || step_size == 0u)
        return 0u;
    return start_size +
           cmp_size +
           2u +
           4u +
           3u +
           step_size +
           2u +
           5u;
}

uint host_open_path_buffer_size(uint packed, uint dst)
{
    uint path_ptr = packed_reg_a(packed);
    uint path_len = packed_reg_b(packed);
    uint load_ptr = host_arg_source_r32_size(X86_REG_R8D, path_ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_R9D, path_len);
    uint len_check = cmp_r32_imm_size(X86_REG_R9D, HOST_PATH_MAX_BYTES);
    uint copy_size = host_path_buffer_copy_size();
    if (load_ptr == 0u || load_len == 0u || len_check == 0u || copy_size == 0u || !valid_reg(dst))
        return 0u;
    uint finish_size = host_path_open_finish_size(dst);
    uint normal_size = copy_size +
                       mov_r32_imm32_size(X86_REG_ESI) +
                       mov_r32_imm32_size(X86_REG_EDX) +
                       mov_r32_imm32_size(X86_REG_EAX) +
                       2u +
                       finish_size;
    uint fail_size = mov_r32_imm32_size(X86_REG_EAX) + finish_size;
    return print_save_restore_size() +
           4u +
           load_ptr +
           load_len +
           7u +
           len_check +
           2u +
           normal_size +
           2u +
           fail_size;
}

uint host_path_syscall_size(uint packed, uint dst, bool has_mode)
{
    uint path_ptr = packed_reg_a(packed);
    uint path_len = packed_reg_b(packed);
    uint load_ptr = host_arg_source_r32_size(X86_REG_R8D, path_ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_R9D, path_len);
    uint len_check = cmp_r32_imm_size(X86_REG_R9D, HOST_PATH_MAX_BYTES);
    uint copy_size = host_path_buffer_copy_size();
    if (load_ptr == 0u || load_len == 0u || len_check == 0u || copy_size == 0u || !valid_reg(dst))
        return 0u;
    uint finish_size = host_path_open_finish_size(dst);
    uint normal_size = copy_size +
                       (has_mode ? mov_r32_imm32_size(X86_REG_ESI) : 0u) +
                       mov_r32_imm32_size(X86_REG_EAX) + 2u + finish_size;
    uint fail_size = mov_r32_imm32_size(X86_REG_EAX) + finish_size;
    return print_save_restore_size() + 4u + load_ptr + load_len + 7u +
           len_check + 2u + normal_size + 2u + fail_size;
}

uint host_rename_path_buffer_size(uint from_packed, uint to_packed, uint dst)
{
    uint from_ptr = packed_reg_a(from_packed);
    uint from_len = packed_reg_b(from_packed);
    uint to_ptr = packed_reg_a(to_packed);
    uint to_len = packed_reg_b(to_packed);
    uint loads = host_arg_source_r32_size(X86_REG_R8D, from_ptr) +
                 host_arg_source_r32_size(X86_REG_R9D, from_len) +
                 host_arg_source_r32_size(X86_REG_R10D, to_ptr) +
                 host_arg_source_r32_size(X86_REG_R11D, to_len);
    uint from_check = cmp_r32_imm_size(X86_REG_R9D, HOST_PATH_MAX_BYTES);
    uint to_check = cmp_r32_imm_size(X86_REG_R11D, HOST_PATH_MAX_BYTES);
    uint copy_size = host_path_buffer_copy_size();
    uint second_copy_size = lea_r64_rsp_size(X86_REG_ESI, HOST_PATH_BUFFER_BYTES) +
                            xor_r32_self_size(X86_REG_ECX) +
                            cmp_r32_r32_size(X86_REG_ECX, X86_REG_R11D) +
                            2u + 4u + 3u + add_r32_imm8_size(X86_REG_ECX) + 2u + 5u;
    uint finish_size = 14u + print_save_restore_size() +
                       (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
    if (loads == 0u || from_check == 0u || to_check == 0u || copy_size == 0u ||
        second_copy_size == 0u || !valid_reg(dst))
        return 0u;
    uint normal_size = copy_size + second_copy_size + mov_r32_imm32_size(X86_REG_EAX) + 2u + finish_size;
    uint fail_size = mov_r32_imm32_size(X86_REG_EAX) + finish_size;
    return print_save_restore_size() + 4u + loads + 7u + from_check + 2u +
           to_check + 2u + normal_size + 2u + fail_size;
}

uint host_result_i32_finish_size(uint dst)
{
    return 8u + print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_clock_read_size(uint packed, uint dst)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    uint load_ptr = host_arg_source_r32_size(X86_REG_ESI, ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_R9D, len);
    uint len_check = cmp_r32_imm_size(X86_REG_R9D, 16u);
    uint finish = host_result_i32_finish_size(dst);
    if (load_ptr == 0u || load_len == 0u || len_check == 0u || !valid_reg(dst))
        return 0u;
    uint normal = mov_r32_imm32_size(X86_REG_EDI) + mov_r32_imm32_size(X86_REG_EAX) + 2u + finish;
    uint fail = mov_r32_imm32_size(X86_REG_EAX) + finish;
    return print_save_restore_size() + 4u + load_ptr + load_len + len_check + 2u + normal + 2u + fail;
}

uint host_sleep_ms_i32_size(uint milliseconds, uint dst)
{
    uint load_ms = host_arg_source_r32_size(X86_REG_R10D, milliseconds);
    uint negative_check = cmp_r32_imm_size(X86_REG_R10D, 0u);
    uint finish = host_result_i32_finish_size(dst);
    if (load_ms == 0u || negative_check == 0u || !valid_reg(dst))
        return 0u;
    uint normal = mov_r32_r32_size(X86_REG_EDX, X86_REG_R10D) +
                  xor_r32_self_size(X86_REG_EDI) + xor_r32_self_size(X86_REG_ESI) +
                  mov_r32_imm32_size(X86_REG_EAX) + 2u + finish;
    uint fail = mov_r32_imm32_size(X86_REG_EAX) + finish;
    return print_save_restore_size() + 4u + load_ms + negative_check + 2u + normal + 2u + fail;
}

uint host_realloc_size(uint old_packed, uint new_packed, uint dst)
{
    uint ptr = packed_reg_a(old_packed);
    uint old_size = packed_reg_b(old_packed);
    uint new_size = packed_reg_a(new_packed);
    uint loads = host_arg_source_r32_size(X86_REG_EDI, ptr) +
                 host_arg_source_r32_size(X86_REG_ESI, old_size) +
                 host_arg_source_r32_size(X86_REG_EDX, new_size);
    if (loads == 0u || !valid_reg(dst))
        return 0u;
    return print_save_restore_size() + 4u + loads +
           mov_r32_imm32_size(X86_REG_R10D) + mov_r32_imm32_size(X86_REG_EAX) + 2u +
           2u + 2u + xor_r32_self_size(X86_REG_EAX) + host_result_i32_finish_size(dst);
}

uint host_write_byte_size(uint packed, uint value, uint dst, bool immediate_newline)
{
    uint handle = packed_reg_a(packed);
    if (!valid_reg(handle) || !valid_reg(dst) || (!immediate_newline && !valid_reg(value)))
        return 0u;
    uint value_move = immediate_newline ? 0u : mov_r32_r32_size(X86_REG_EDX, value);
    uint byte_store = immediate_newline ? 3u : 2u;
    return print_save_restore_size() + 4u +
           (handle == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, handle)) +
           value_move + 5u + byte_store +
           mov_r32_imm32_size(X86_REG_EDX) +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u + 4u +
           print_save_restore_size() +
           xor_r32_self_size(dst);
}

uint host_read_i32_size(uint packed, uint dst)
{
    uint handle = packed_reg_a(packed);
    uint fallback = packed_reg_b(packed);
    if (!valid_reg(handle) || !valid_reg(fallback) || !valid_reg(dst))
        return 0u;
    return print_save_restore_size() + 4u +
           (handle == X86_REG_R8D ? 0u : mov_r32_r32_size(X86_REG_R8D, handle)) +
           (fallback == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, fallback)) +
           4u + 84u + 4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_fs_close_size(uint packed)
{
    uint handle = packed_reg_a(packed);
    uint dst = packed_reg_b(packed);
    uint load_handle = host_arg_source_r32_size(X86_REG_EDI, handle);
    if (load_handle == 0u || !valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           4u +
           load_handle +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           4u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_fs_read_write_size(uint packed, uint len, uint dst)
{
    uint handle = packed_reg_a(packed);
    uint ptr = packed_reg_b(packed);
    uint load_handle = host_arg_source_r32_size(X86_REG_EDI, handle);
    uint load_ptr = host_arg_source_r32_size(X86_REG_ESI, ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_EDX, len);
    if (load_handle == 0u || load_ptr == 0u || load_len == 0u || !valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           4u +
           load_handle +
           load_ptr +
           load_len +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           4u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_stdio_read_write_size(uint packed, uint dst)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    uint load_ptr = host_arg_source_r32_size(X86_REG_ESI, ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_EDX, len);
    if (load_ptr == 0u || load_len == 0u || !valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           4u +
           mov_r32_imm32_size(X86_REG_EDI) +
           load_ptr +
           load_len +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           4u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint load_rsp_disp8_r32_size(uint dst)
{
    return valid_reg(dst) ? 4u + rex_for_modrm(dst, 4u) : 0u;
}

uint host_secure_u32_size(uint dst)
{
    if (!valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           4u +
           xor_r32_self_size(X86_REG_EAX) +
           4u +
           5u +
           mov_r32_imm32_size(X86_REG_ESI) +
           xor_r32_self_size(X86_REG_EDX) +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           load_rsp_disp8_r32_size(X86_REG_EAX) +
           4u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_fill_secure_bytes_size(uint packed, uint dst)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    uint load_ptr = host_arg_source_r32_size(X86_REG_EDI, ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_ESI, len);
    if (load_ptr == 0u || load_len == 0u || !valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           4u +
           load_ptr +
           load_len +
           xor_r32_self_size(X86_REG_EDX) +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           4u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_alloc_size(uint packed, uint dst)
{
    uint size = packed_reg_a(packed);
    uint align = packed_reg_b(packed);
    if (!valid_reg(size) || !valid_reg(align) || !valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           (size == X86_REG_ESI ? 0u : mov_r32_r32_size(X86_REG_ESI, size)) +
           xor_r32_self_size(X86_REG_EDI) +
           mov_r32_imm32_size(X86_REG_EDX) +
           mov_r32_imm32_size(X86_REG_R10D) +
           mov_r32_imm32_size(X86_REG_R8D) +
           xor_r32_self_size(X86_REG_R9D) +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           2u +
           2u +
           xor_r32_self_size(X86_REG_EAX) +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_dealloc_size(uint packed, uint align)
{
    uint ptr = packed_reg_a(packed);
    uint size = packed_reg_b(packed);
    if (!valid_reg(ptr) || !valid_reg(size) || !valid_reg(align))
        return 0u;
    return print_save_restore_size() +
           (ptr == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, ptr)) +
           (size == X86_REG_ESI ? 0u : mov_r32_r32_size(X86_REG_ESI, size)) +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           print_save_restore_size();
}

uint load_process_stack_r32_size(uint dst)
{
    return valid_reg(dst) ? 2u + rex_for_modrm(dst, X86_REG_R15D) : 0u;
}

uint host_unix_seconds_size(uint dst)
{
    if (!valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           xor_r32_self_size(X86_REG_EDI) +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_arg_len_size(uint index, uint dst)
{
    if (!valid_reg(index) || !valid_reg(dst))
        return 0u;
    uint load_index = host_arg_source_r32_size(X86_REG_EDI, index);
    if (load_index == 0u)
        return 0u;
    return print_save_restore_size() +
           4u +
           load_index +
           45u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_arg_read_size(uint packed, uint len, uint dst)
{
    uint index = packed_reg_a(packed);
    uint ptr = packed_reg_b(packed);
    if (!valid_reg(index) || !valid_reg(ptr) || !valid_reg(len) || !valid_reg(dst))
        return 0u;
    uint load_index = host_arg_source_r32_size(X86_REG_EDI, index);
    uint load_ptr = host_arg_source_r32_size(X86_REG_ESI, ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_EDX, len);
    if (load_index == 0u || load_ptr == 0u || load_len == 0u)
        return 0u;
    return print_save_restore_size() +
           4u +
           load_index +
           load_ptr +
           load_len +
           59u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_current_dir_read_size(uint packed, uint dst)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    if (!valid_reg(ptr) || !valid_reg(len) || !valid_reg(dst))
        return 0u;
    uint load_ptr = host_arg_source_r32_size(X86_REG_EDI, ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_ESI, len);
    if (load_ptr == 0u || load_len == 0u)
        return 0u;
    return print_save_restore_size() +
           4u +
           load_ptr +
           load_len +
           mov_r32_imm32_size(X86_REG_EAX) +
           2u +
           31u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_var_count_size(uint dst)
{
    if (!valid_reg(dst))
        return 0u;
    return print_save_restore_size() +
           4u +
           33u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_var_key_len_size(uint index, uint dst)
{
    if (!valid_reg(index) || !valid_reg(dst))
        return 0u;
    uint load_index = host_arg_source_r32_size(X86_REG_EDI, index);
    if (load_index == 0u)
        return 0u;
    return print_save_restore_size() +
           4u +
           load_index +
           60u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_var_key_read_size(uint packed, uint len, uint dst)
{
    uint index = packed_reg_a(packed);
    uint ptr = packed_reg_b(packed);
    if (!valid_reg(index) || !valid_reg(ptr) || !valid_reg(len) || !valid_reg(dst))
        return 0u;
    uint load_index = host_arg_source_r32_size(X86_REG_EDI, index);
    uint load_ptr = host_arg_source_r32_size(X86_REG_ESI, ptr);
    uint load_len = host_arg_source_r32_size(X86_REG_EDX, len);
    if (load_index == 0u || load_ptr == 0u || load_len == 0u)
        return 0u;
    return print_save_restore_size() +
           4u +
           load_index +
           load_ptr +
           load_len +
           72u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_var_len_size(uint packed, uint dst)
{
    uint key_ptr = packed_reg_a(packed);
    uint key_len = packed_reg_b(packed);
    if (!valid_reg(key_ptr) || !valid_reg(key_len) || !valid_reg(dst))
        return 0u;
    uint load_key_ptr = host_arg_source_r32_size(X86_REG_EDI, key_ptr);
    uint load_key_len = host_arg_source_r32_size(X86_REG_ESI, key_len);
    if (load_key_ptr == 0u || load_key_len == 0u)
        return 0u;
    return print_save_restore_size() +
           4u +
           load_key_ptr +
           load_key_len +
           84u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_var_read_size(uint key_pair, uint value_pair, uint dst)
{
    uint key_ptr = packed_reg_a(key_pair);
    uint key_len = packed_reg_b(key_pair);
    uint value_ptr = packed_reg_a(value_pair);
    uint value_len = packed_reg_b(value_pair);
    if (!valid_reg(key_ptr) || !valid_reg(key_len) || !valid_reg(value_ptr) || !valid_reg(value_len) || !valid_reg(dst))
        return 0u;
    uint load_key_ptr = host_arg_source_r32_size(X86_REG_EDI, key_ptr);
    uint load_key_len = host_arg_source_r32_size(X86_REG_ESI, key_len);
    uint load_value_ptr = host_arg_source_r32_size(X86_REG_EDX, value_ptr);
    uint load_value_len = host_arg_source_r32_size(X86_REG_ECX, value_len);
    if (load_key_ptr == 0u || load_key_len == 0u || load_value_ptr == 0u || load_value_len == 0u)
        return 0u;
    return print_save_restore_size() +
           4u +
           load_key_ptr +
           load_key_len +
           load_value_ptr +
           load_value_len +
           106u +
           4u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_write_i32_size(uint packed, uint dst)
{
    uint handle = packed_reg_a(packed);
    uint value = packed_reg_b(packed);
    if (!valid_reg(handle) || !valid_reg(value) || !valid_reg(dst))
        return 0u;
    uint base = print_i32_size(value);
    uint fd_save = handle == X86_REG_R9D ? 0u : mov_r32_r32_size(X86_REG_R9D, handle);
    uint fd_use = mov_r32_r32_size(X86_REG_EDI, X86_REG_R9D);
    uint stdout_fd_move = mov_r32_imm32_size(X86_REG_EDI);
    if (base == 0u || fd_use == 0u)
        return 0u;
    return base + fd_save + fd_use - stdout_fd_move - 3u + xor_r32_self_size(dst);
}

uint exit_zero_size()
{
    return exit_code_size(0u);
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

uint selected_mixed_payload_row(uint payload_base, uint ordinal)
{
    if (payload_base == INVALID || ordinal >= 6u)
        return INVALID;
    uint row = payload_base + ordinal / 3u;
    return row < gParams.inst_capacity ? row : INVALID;
}

uint selected_mixed_arg_kind(uint info, uint payload_base, uint ordinal)
{
    uint row = selected_mixed_payload_row(payload_base, ordinal);
    if (row != INVALID)
        return packed_u2_at_offset(x86_inst_kind[row], 8u, ordinal % 3u);
    return 0u;
}

uint selected_mixed_arg_payload(uint info, uint payload_base, uint ordinal)
{
    uint arg_count = packed_u8_at(info, 2u);
    if (ordinal >= arg_count)
        return INVALID;
    uint row = selected_mixed_payload_row(payload_base, ordinal);
    if (row == INVALID)
        return INVALID;
    uint slot = ordinal % 3u;
    if (slot == 0u) return x86_inst_arg0[row];
    if (slot == 1u) return x86_inst_arg1[row];
    if (slot == 2u) return x86_inst_arg2[row];
    return 0xffffffffu;
}

bool selected_mixed_payload_rows_valid(uint payload_base, uint arg_count)
{
    if (arg_count == 0u)
        return true;
    return selected_mixed_payload_row(payload_base, arg_count - 1u) != INVALID;
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
    {
        uint base = param_aggregate_payload_base(payload);
        uint ordinal = param_aggregate_payload_ordinal(payload);
        uint saved_load_size = load_saved_call_reg_r64_size(target, base, save_mask);
        if (saved_load_size != 0u)
            return saved_load_size +
                   (ordinal == 0u ? 0u : lea_arg_param_ptr_size(target, pack_u16_pair(target, ordinal)));
        if (ordinal == 0u)
            return base == target ? 0u : mov_r64_r64_size(target, base);
        return lea_arg_param_ptr_size(target, payload);
    }
    return 0u;
}

uint call_mixed_ordinal_move_size(
    uint info,
    uint packed,
    uint save_mask,
    uint save_stack,
    uint ordinal,
    uint arg_count,
    bool aggregate_return)
{
    if (ordinal >= arg_count)
        return 0u;
    uint target_reg = mixed_target_reg(ordinal, aggregate_return);
    if (!valid_reg(target_reg))
        return 0xffffffffu;
    uint payload = selected_mixed_arg_payload(info, packed, ordinal);
    uint kind = selected_mixed_arg_kind(info, packed, ordinal);
    uint move_size = mixed_arg_move_size(target_reg, kind, payload, save_mask, save_stack);
    if (move_size == 0u &&
        !(kind == X86_ARG_SCALAR && payload == target_reg) &&
        !(kind == X86_ARG_PARAM_PTR &&
          param_aggregate_payload_ordinal(payload) == 0u &&
          param_aggregate_payload_base(payload) == target_reg))
        return 0xffffffffu;
    return move_size;
}

uint call_mixed_size(uint target, uint info, uint packed, uint save_mask)
{
    bool aggregate_return = (info & 1u) != 0u;
    uint dest = packed_u8_at(info, 1u);
    uint arg_count = packed_u8_at(info, 2u);
    if (arg_count > 6u || (aggregate_return && dest != X86_AGG_RETURN_DEST_RET_PTR && !valid_local_slot(dest)) ||
        (!aggregate_return && !valid_reg(dest)) ||
        !selected_mixed_payload_rows_valid(packed, arg_count))
        return 0u;

    uint save_size = call_save_restore_size(save_mask);
    uint save_stack = call_save_stack_size(save_mask);
    uint size = save_size;
    if (aggregate_return && dest != X86_AGG_RETURN_DEST_RET_PTR)
        size += lea_arg_local_ptr_size(X86_REG_EDI, dest, save_stack);

    uint move0 = call_mixed_ordinal_move_size(info, packed, save_mask, save_stack, 0u, arg_count, aggregate_return);
    uint move1 = call_mixed_ordinal_move_size(info, packed, save_mask, save_stack, 1u, arg_count, aggregate_return);
    uint move2 = call_mixed_ordinal_move_size(info, packed, save_mask, save_stack, 2u, arg_count, aggregate_return);
    uint move3 = call_mixed_ordinal_move_size(info, packed, save_mask, save_stack, 3u, arg_count, aggregate_return);
    uint move4 = call_mixed_ordinal_move_size(info, packed, save_mask, save_stack, 4u, arg_count, aggregate_return);
    uint move5 = call_mixed_ordinal_move_size(info, packed, save_mask, save_stack, 5u, arg_count, aggregate_return);
    if (move0 == 0xffffffffu || move1 == 0xffffffffu ||
        move2 == 0xffffffffu || move3 == 0xffffffffu ||
        move4 == 0xffffffffu || move5 == 0xffffffffu)
        return 0u;
    size += move0 + move1 + move2 + move3 + move4 + move5;

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
        uint load_size = local_mem_r32_size(X86_REG_R11D, payload);
        uint store_size = ptr_slot_mem_r32_size(X86_REG_R11D, X86_REG_EDI, ordinal);
        return load_size != 0u && store_size != 0u ? load_size + store_size : 0u;
    }
    if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint payload_base = payload & 0x0fu;
        uint payload_ordinal = payload >> 4u;
        uint load_size = ptr_slot_mem_r32_size(X86_REG_R11D, payload_base, payload_ordinal);
        uint store_size = ptr_slot_mem_r32_size(X86_REG_R11D, X86_REG_EDI, ordinal);
        return load_size != 0u && store_size != 0u ? load_size + store_size : 0u;
    }
    if (source_kind == X86_AGG_SOURCE_REG)
        return ptr_slot_mem_r32_size(payload, X86_REG_EDI, ordinal);
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

bool inst_target_valid(uint target)
{
    return target <= select_status[3u];
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
    if (kind == X86_INST_V_COMPARE_R32_R32) return compare_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_RETURN_R32) return return_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_HOST_PROCESS_EXIT) return return_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_BRANCH_ZERO) return inst_target_valid(x86_inst_arg1[inst_i]) ? branch_zero_size(x86_inst_arg0[inst_i]) : 0u;
    if (kind == X86_INST_V_JMP) return inst_target_valid(x86_inst_arg0[inst_i]) ? 5u : 0u;
    if (kind == X86_INST_V_PARAM_R32) return mov_r32_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_RETURN_FUNC_R32) return return_func_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_PRINT_I32) return print_i32_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_HOST_TEXT_WRITE) return host_text_write_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_OPEN_WRITE_PATH ||
        kind == X86_INST_V_HOST_OPEN_READ_PATH)
        return host_open_path_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_WRITE_I32) return host_write_i32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_READ_I32) return host_read_i32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_WRITE_BYTE) return host_write_byte_size(x86_inst_arg0[inst_i], packed_reg_b(x86_inst_arg0[inst_i]), x86_inst_arg1[inst_i], false);
    if (kind == X86_INST_V_HOST_WRITE_NEWLINE) return host_write_byte_size(x86_inst_arg0[inst_i], 0u, packed_reg_b(x86_inst_arg0[inst_i]), true);
    if (kind == X86_INST_V_HOST_SECURE_U32) return host_secure_u32_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_HOST_ALLOC) return host_alloc_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_DEALLOC) return host_dealloc_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_ARGC) return load_process_stack_r32_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_HOST_UNIX_SECONDS) return host_unix_seconds_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_HOST_ARG_LEN) return host_arg_len_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_ARG_READ) return host_arg_read_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_CURRENT_DIR_READ) return host_current_dir_read_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_VAR_COUNT) return host_var_count_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_HOST_VAR_KEY_LEN) return host_var_key_len_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_VAR_KEY_READ) return host_var_key_read_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_VAR_LEN) return host_var_len_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_VAR_READ) return host_var_read_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_CLOSE_FILE) return host_fs_close_size(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_HOST_FS_READ ||
        kind == X86_INST_V_HOST_FS_WRITE)
        return host_fs_read_write_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_FS_OPEN_READ ||
        kind == X86_INST_V_HOST_FS_OPEN_WRITE ||
        kind == X86_INST_V_HOST_FS_OPEN_APPEND)
        return host_open_path_buffer_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_STDIN_READ ||
        kind == X86_INST_V_HOST_STDOUT_WRITE ||
        kind == X86_INST_V_HOST_STDERR_WRITE)
        return host_stdio_read_write_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_FILL_SECURE_BYTES)
        return host_fill_secure_bytes_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_FS_REMOVE_FILE ||
        kind == X86_INST_V_HOST_FS_REMOVE_DIR)
        return host_path_syscall_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], false);
    if (kind == X86_INST_V_HOST_FS_CREATE_DIR)
        return host_path_syscall_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], true);
    if (kind == X86_INST_V_HOST_FS_RENAME)
        return host_rename_path_buffer_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_TIME_MONOTONIC_READ ||
        kind == X86_INST_V_HOST_TIME_SYSTEM_READ)
        return host_clock_read_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_TIME_SLEEP_MS_I32)
        return host_sleep_ms_i32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_HOST_REALLOC)
        return host_realloc_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_HOST_ALLOC_FAILED)
        return 12u;
    if (kind == X86_INST_V_LOAD_LOCAL_R32) return local_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_STORE_LOCAL_R32) return local_mem_r32_size(x86_inst_arg1[inst_i], x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_LOAD_LOCAL_INDEX_R32) return checked_local_index_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_STORE_LOCAL_INDEX_R32) return checked_local_index_mem_r32_size(x86_inst_arg2[inst_i], x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_STORE_PARAM_INDEX_R32) return checked_param_index_mem_r32_size(x86_inst_arg2[inst_i], x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_STORE_LOCAL_IMM32) return local_imm32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_STORE_LOCAL_RODATA_PTR) return local_imm32_size(x86_inst_arg0[inst_i], 1u);
    if (kind == X86_INST_V_FOR_ARRAY_BRANCH) return inst_target_valid(x86_inst_arg2[inst_i]) ? for_array_branch_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]) : 0u;
    if (kind == X86_INST_V_FOR_ARRAY_LOAD) return for_array_load_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_FOR_PARAM_ARRAY_LOAD) return for_param_array_load_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_FOR_ARRAY_INC_JMP) return inst_target_valid(x86_inst_arg1[inst_i]) ? for_array_inc_jmp_size(x86_inst_arg0[inst_i], x86_inst_arg2[inst_i]) : 0u;
    if (kind == X86_INST_V_FOR_INTERVAL_BRANCH) return inst_target_valid(x86_inst_arg2[inst_i]) ? for_interval_branch_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]) : 0u;
    if (kind == X86_INST_V_COPY_LOCAL_R32) return copy_local_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_CALL_MIXED_DIRECT) return inst_target_valid(x86_inst_arg0[inst_i]) ? call_mixed_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], inst_call_save_mask(inst_i)) : 0u;
    if (kind == X86_INST_V_CALL_MIXED_EXTERNAL) return call_mixed_size(0u, x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], inst_call_save_mask(inst_i));
    if (kind == X86_INST_V_LOAD_PARAM_INDEX_R32) return checked_param_index_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_STORE_RET_PTR_R32) return ptr_slot_mem_r32_size(x86_inst_arg0[inst_i], X86_REG_EDI, x86_inst_arg1[inst_i]);
    if (kind == X86_INST_V_COPY_AGG_RET) return copy_agg_ret_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_STORE_RET_PTR_IMM32) return ptr_slot_imm32_size(X86_REG_EDI, x86_inst_arg1[inst_i], x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_LOAD_PTR_SLOT_R32) return ptr_slot_mem_r32_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i]);
    if (kind == X86_INST_V_MATCH_TAG_BRANCH) return inst_target_valid(x86_inst_arg2[inst_i]) ? match_tag_branch_size(unpack_u16_pair_low(x86_inst_arg0[inst_i]), unpack_u16_pair_high(x86_inst_arg0[inst_i]), x86_inst_arg1[inst_i]) : 0u;
    if (kind == X86_INST_V_ENTRY_STACK_JMP) return inst_target_valid(x86_inst_arg0[inst_i]) ? process_stack_save_size() + stack_frame_adjust_size(x86_inst_arg1[inst_i]) + 5u : 0u;
    if (kind == X86_INST_V_EXIT_ZERO) return exit_zero_size();
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint inst_i = linear_dispatch_id(tid);
    bool select_ok = select_status[0u] == X86_SELECT_OK &&
                     select_status[1u] == 0u &&
                     select_status[3u] <= gParams.inst_capacity;
    uint inst_count = select_ok ? select_status[3u] : 0u;

    if (inst_i == 0u)
    {
        uint upstream_error = select_status[1u] == 0u ? X86_ERR_INST_SIZE : select_status[1u];
        size_status[0u] = select_ok ? X86_SIZE_OK : 0u;
        size_status[1u] = select_ok ? 0u : upstream_error;
        size_status[2u] = select_ok ? 0xffffffffu : select_status[2u];
        size_status[3u] = inst_count;
    }

    if (!select_ok || inst_i >= inst_count)
        return;

    uint size = byte_size_for_inst(inst_i);
    x86_inst_size[inst_i] = size;
    if ((size == 0u && inst_kind_tag(inst_i) != 0u) ||
        size > X86_MAX_ENCODED_INST_BYTES)
        publish_stage_error_min_detail4(size_status, X86_ERR_INST_SIZE, inst_i);
}
