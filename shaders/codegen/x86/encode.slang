// Direct x86_64 instruction encoder.
//
// This pass consumes instruction records plus GPU-computed byte offsets and
// scatters packed `.text` bytes directly into their final ELF output offset.
// ELF construction fills the header bytes without knowing instruction template
// details.

import gpu_index;
import byte_packing;
import bit_packing;
import atomics;
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
StructuredBuffer<uint> x86_decl_layout_status;
StructuredBuffer<uint> x86_text_len;
StructuredBuffer<uint> x86_rodata_size_by_node;
StructuredBuffer<uint> x86_rodata_offset_by_node;
StructuredBuffer<uint> text_status;
StructuredBuffer<uint> reloc_status;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> encode_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_TEXT_OK = 1u;
static const uint X86_RELOC_OK = 1u;
static const uint X86_ENCODE_OK = 1u;
static const uint INVALID = 0xffffffffu;
static const uint X86_ERR_OUTPUT_TOO_SMALL = 4u;
static const uint X86_ERR_RELOC = 8u;
// Local byte budget for one selected instruction. Source/program-sized work is
// partitioned by dispatch rows and prefix-summed byte offsets before this pass.
static const uint X86_MAX_ENCODED_INST_BYTES = 256u;
static const uint ELF_TEXT_OFFSET = 0x78u;
static const uint ELF_TEXT_WORD_OFFSET = ELF_TEXT_OFFSET / 4u;
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
static const uint HOST_PATH_RESULT_DISP = 4160u;
static const uint HOST_RENAME_BUFFER_BYTES = 8192u;
static const uint HOST_RENAME_RESULT_DISP = 8256u;
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
static const uint X86_CMP_LT = 1u;
static const uint X86_CMP_GT = 2u;
static const uint X86_CMP_LE = 3u;
static const uint X86_CMP_GE = 4u;
static const uint X86_CMP_EQ = 5u;
static const uint X86_CMP_NE = 6u;
static const uint X86_CMP_UNSIGNED_FLAG = 0x80u;
static const uint X86_CMP_FLOAT_FLAG = 0x40u;
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

uint le32_byte(uint value, uint byte_i)
{
    return u32_le_byte(value, byte_i);
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
    if (exp == 0u) return 1u;
    if (exp == 1u) return 10u;
    if (exp == 2u) return 100u;
    if (exp == 3u) return 1000u;
    if (exp == 4u) return 10000u;
    if (exp == 5u) return 100000u;
    if (exp == 6u) return 1000000u;
    if (exp == 7u) return 10000000u;
    if (exp == 8u) return 100000000u;
    return 1000000000u;
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
    uint base = compare_op & ~(X86_CMP_UNSIGNED_FLAG | X86_CMP_FLOAT_FLAG);
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
    uint base = compare_op & ~(X86_CMP_UNSIGNED_FLAG | X86_CMP_FLOAT_FLAG);
    bool unsigned_mode = (compare_op & (X86_CMP_UNSIGNED_FLAG | X86_CMP_FLOAT_FLAG)) != 0u;
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

bool valid_index_reg(uint reg)
{
    return valid_reg(reg) && (reg & 7u) != 4u;
}

bool needs_rex_opcode_reg(uint reg)
{
    return reg >= 8u && reg < 16u;
}

bool needs_rex_modrm(uint reg_field, uint rm)
{
    return (reg_field >= 8u && reg_field < 16u) || (rm >= 8u && rm < 16u);
}

bool needs_rex_sib(uint reg_field, uint index, uint base)
{
    return (reg_field >= 8u && reg_field < 16u) ||
           (index >= 8u && index < 16u) ||
           (base >= 8u && base < 16u);
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

uint rex_sib(uint reg_field, uint index, uint base)
{
    return 0x40u |
           (((reg_field >> 3u) & 1u) << 2u) |
           (((index >> 3u) & 1u) << 1u) |
           ((base >> 3u) & 1u);
}

uint rex64_modrm(uint reg_field, uint rm)
{
    return 0x48u | (((reg_field >> 3u) & 1u) << 2u) | ((rm >> 3u) & 1u);
}

uint rex64_sib(uint reg_field, uint index, uint base)
{
    return 0x48u |
           (((reg_field >> 3u) & 1u) << 2u) |
           (((index >> 3u) & 1u) << 1u) |
           ((base >> 3u) & 1u);
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
    return packed_u8_at(packed, 0u);
}

uint packed_reg_b(uint packed)
{
    return packed_u8_at(packed, 1u);
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

bool signed_i8_immediate(uint imm)
{
    return imm <= 127u || imm >= 0xffffff80u;
}

uint push_imm8_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x6au;
    if (byte_i == 1u) return imm & 0xffu;
    return 0u;
}

uint mov_r32_imm_compact_byte(uint dst, uint imm, uint byte_i)
{
    if (valid_reg(dst) && imm == 0u)
        return xor_r32_r32_byte(dst, byte_i);
    if (dst != X86_REG_ESP && signed_i8_immediate(imm))
    {
        if (byte_i < 2u)
            return push_imm8_byte(imm, byte_i);
        return pop_r64_byte(dst, byte_i - 2u);
    }
    return mov_r32_imm32_byte(dst, imm, byte_i);
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

uint local_slot_disp(uint slot)
{
    return (slot + 3u) * 4u;
}

bool valid_local_slot(uint slot)
{
    return slot < MAX_X86_LOCAL_SLOTS;
}

uint local_mem_r32_size(uint reg, uint slot)
{
    if (!valid_reg(reg) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    return (disp <= 127u ? 4u : 7u) + (needs_rex_modrm(reg, 4u) ? 1u : 0u);
}

uint param_index_mem_r32_size(uint dst, uint base, uint index)
{
    return valid_reg(dst) && valid_reg(base) && valid_index_reg(index) && (base & 7u) != 4u
               ? 4u + (needs_rex_sib(dst, index, base) ? 1u : 0u)
               : 0u;
}

uint param_index_slot_mem_r32_size(uint dst, uint base, uint index, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(dst) && valid_reg(base) && valid_index_reg(index) &&
                   (base & 7u) != 4u
               ? (disp <= 127u ? 4u : 7u) + (needs_rex_sib(dst, index, base) ? 1u : 0u)
               : 0u;
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

uint ptr_slot_mem_r32_size(uint reg, uint base, uint ordinal)
{
    uint disp = ordinal * 4u;
    return valid_reg(reg) && valid_reg(base)
               ? (disp <= 127u ? 3u : 6u) + (needs_rex_modrm(reg, base) ? 1u : 0u)
               : 0u;
}

uint rodata_payload_len_for_node(uint node, uint fallback_len)
{
    if (node >= gParams.n_hir_nodes)
        return fallback_len;

    uint size = x86_rodata_size_by_node[node];
    if (size == 0u)
        return fallback_len;
    return size - 1u;
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
        return (disp <= 127u ? 4u : 7u) + (needs_rex_modrm(7u, base) ? 1u : 0u);
    return (disp <= 127u ? 7u : 10u) + (needs_rex_modrm(7u, base) ? 1u : 0u);
}

uint load_local_r32_byte(uint dst, uint slot, uint byte_i)
{
    bool rex = needs_rex_modrm(dst, 4u);
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return (disp8 ? 0x44u : 0x84u) | ((dst & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x24u;
    if (disp8 && byte_i == cursor + 3u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 3u && byte_i < cursor + 7u)
        return le32_byte(disp, byte_i - cursor - 3u);
    return 0u;
}

uint load_local_r32_adjusted_byte(uint dst, uint slot, uint stack_adjust, uint byte_i)
{
    bool rex = needs_rex_modrm(dst, 4u);
    uint disp = local_slot_disp(slot) + stack_adjust;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return (disp8 ? 0x44u : 0x84u) | ((dst & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x24u;
    if (disp8 && byte_i == cursor + 3u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 3u && byte_i < cursor + 7u)
        return le32_byte(disp, byte_i - cursor - 3u);
    return 0u;
}

uint load_rsp_disp8_r32_byte(uint dst, uint disp, uint byte_i)
{
    bool rex = needs_rex_modrm(dst, 4u);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return 0x44u | ((dst & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x24u;
    if (byte_i == cursor + 3u) return disp & 0xffu;
    return 0u;
}

uint local_mem_r32_adjusted_size(uint reg, uint slot, uint stack_adjust)
{
    if (!valid_reg(reg) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot) + stack_adjust;
    return (disp <= 127u ? 4u : 7u) + (needs_rex_modrm(reg, 4u) ? 1u : 0u);
}

uint store_local_r32_byte(uint slot, uint src, uint byte_i)
{
    bool rex = needs_rex_modrm(src, 4u);
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(src, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x89u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x44u : 0x84u) | ((src & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x24u;
    if (disp8 && byte_i == cursor + 3u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 3u && byte_i < cursor + 7u)
        return le32_byte(disp, byte_i - cursor - 3u);
    return 0u;
}

uint lea_r64_rsp_disp8_byte(uint dst, uint disp, uint byte_i)
{
    if (byte_i == 0u) return rex64_modrm(dst, 4u);
    if (byte_i == 1u) return 0x8du;
    if (byte_i == 2u) return 0x44u | ((dst & 7u) << 3u);
    if (byte_i == 3u) return 0x24u;
    if (byte_i == 4u) return disp & 0xffu;
    return 0u;
}

uint lea_r64_rsp_disp32_byte(uint dst, uint disp, uint byte_i)
{
    if (byte_i == 0u) return rex64_modrm(dst, 4u);
    if (byte_i == 1u) return 0x8du;
    if (byte_i == 2u) return 0x84u | ((dst & 7u) << 3u);
    if (byte_i == 3u) return 0x24u;
    if (byte_i >= 4u && byte_i < 8u) return le32_byte(disp, byte_i - 4u);
    return 0u;
}

uint lea_r64_rsp_byte(uint dst, uint disp, uint byte_i)
{
    return disp <= 127u ? lea_r64_rsp_disp8_byte(dst, disp, byte_i)
                        : lea_r64_rsp_disp32_byte(dst, disp, byte_i);
}

uint lea_r64_base_disp8_byte(uint dst, uint base, uint disp, uint byte_i)
{
    if (byte_i == 0u) return rex64_modrm(dst, base);
    if (byte_i == 1u) return 0x8du;
    if (byte_i == 2u) return 0x40u | ((dst & 7u) << 3u) | (base & 7u);
    if (byte_i == 3u) return disp & 0xffu;
    return 0u;
}

uint lea_r64_base_disp32_byte(uint dst, uint base, uint disp, uint byte_i)
{
    if (byte_i == 0u) return rex64_modrm(dst, base);
    if (byte_i == 1u) return 0x8du;
    if (byte_i == 2u) return 0x80u | ((dst & 7u) << 3u) | (base & 7u);
    if (byte_i >= 3u && byte_i < 7u) return le32_byte(disp, byte_i - 3u);
    return 0u;
}

uint lea_r64_base_byte(uint dst, uint base, uint disp, uint byte_i)
{
    return disp <= 127u ? lea_r64_base_disp8_byte(dst, base, disp, byte_i)
                        : lea_r64_base_disp32_byte(dst, base, disp, byte_i);
}

uint mov_r64_r64_byte(uint dst, uint src, uint byte_i)
{
    if (byte_i == 0u) return rex64_modrm(src, dst);
    if (byte_i == 1u) return 0x89u;
    if (byte_i == 2u) return modrm(src, dst);
    return 0u;
}

uint load_param_index_slot_r32_byte(uint dst, uint base, uint index, uint ordinal, uint byte_i)
{
    bool rex = needs_rex_sib(dst, index, base);
    uint disp = ordinal * 4u;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_sib(dst, index, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return (disp8 ? 0x44u : 0x84u) | ((dst & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x80u | ((index & 7u) << 3u) | (base & 7u);
    if (disp8 && byte_i == cursor + 3u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 3u && byte_i < cursor + 7u)
        return le32_byte(disp, byte_i - cursor - 3u);
    return 0u;
}

uint load_param_index_r32_byte(uint dst, uint base, uint index, uint byte_i)
{
    return load_param_index_slot_r32_byte(dst, base, index, 0u, byte_i);
}

uint load_ptr_slot_r32_byte(uint dst, uint base, uint ordinal, uint byte_i)
{
    bool rex = needs_rex_modrm(dst, base);
    uint disp = ordinal * 4u;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return (disp8 ? 0x40u : 0x80u) | ((dst & 7u) << 3u) | (base & 7u);
    if (disp8 && byte_i == cursor + 2u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(disp, byte_i - cursor - 2u);
    return 0u;
}

uint store_ptr_slot_r32_byte(uint base, uint src, uint ordinal, uint byte_i)
{
    bool rex = needs_rex_modrm(src, base);
    uint disp = ordinal * 4u;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(src, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x89u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x40u : 0x80u) | ((src & 7u) << 3u) | (base & 7u);
    if (disp8 && byte_i == cursor + 2u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(disp, byte_i - cursor - 2u);
    return 0u;
}

uint store_ptr_slot_imm32_byte(uint base, uint ordinal, uint imm, uint byte_i)
{
    bool rex = needs_rex_modrm(0u, base);
    uint disp = ordinal * 4u;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(0u, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0xc7u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x40u : 0x80u) | (base & 7u);
    if (disp8 && byte_i == cursor + 2u) return disp & 0xffu;
    if (disp8 && byte_i < cursor + 7u) return le32_byte(imm, byte_i - cursor - 3u);
    if (!disp8 && byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(disp, byte_i - cursor - 2u);
    if (!disp8 && byte_i < cursor + 10u) return le32_byte(imm, byte_i - cursor - 6u);
    return 0u;
}

uint store_ptr_slot_zero_byte(uint base, uint ordinal, uint byte_i)
{
    bool rex = needs_rex_modrm(4u, base);
    uint disp = ordinal * 4u;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(4u, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x83u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x60u : 0xa0u) | (base & 7u);
    if (disp8 && byte_i == cursor + 2u) return disp & 0xffu;
    if (disp8 && byte_i == cursor + 3u) return 0u;
    if (!disp8 && byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(disp, byte_i - cursor - 2u);
    if (!disp8 && byte_i == cursor + 6u) return 0u;
    return 0u;
}

uint cmp_ptr_slot_imm32_byte(uint base, uint ordinal, uint imm, uint byte_i)
{
    bool rex = needs_rex_modrm(7u, base);
    uint disp = ordinal * 4u;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(7u, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x81u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x78u : 0xb8u) | (base & 7u);
    if (disp8 && byte_i == cursor + 2u) return disp & 0xffu;
    if (disp8 && byte_i < cursor + 7u) return le32_byte(imm, byte_i - cursor - 3u);
    if (!disp8 && byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(disp, byte_i - cursor - 2u);
    if (!disp8 && byte_i < cursor + 10u) return le32_byte(imm, byte_i - cursor - 6u);
    return 0u;
}

uint cmp_ptr_slot_imm_byte(uint base, uint ordinal, uint imm, uint byte_i)
{
    bool rex = needs_rex_modrm(7u, base);
    bool imm8 = signed_i8_immediate(imm);
    uint disp = ordinal * 4u;
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(7u, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return imm8 ? 0x83u : 0x81u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x78u : 0xb8u) | (base & 7u);
    if (disp8 && byte_i == cursor + 2u) return disp & 0xffu;
    if (disp8 && imm8 && byte_i == cursor + 3u) return imm & 0xffu;
    if (disp8 && !imm8 && byte_i < cursor + 7u) return le32_byte(imm, byte_i - cursor - 3u);
    if (!disp8 && byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(disp, byte_i - cursor - 2u);
    if (!disp8 && imm8 && byte_i == cursor + 6u) return imm & 0xffu;
    if (!disp8 && !imm8 && byte_i < cursor + 10u) return le32_byte(imm, byte_i - cursor - 6u);
    return 0u;
}

uint load_local_index_r32_byte(uint dst, uint slot, uint index, uint byte_i)
{
    bool rex = needs_rex_sib(dst, index, 4u);
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_sib(dst, index, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return (disp8 ? 0x44u : 0x84u) | ((dst & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x84u | ((index & 7u) << 3u);
    if (disp8 && byte_i == cursor + 3u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 3u && byte_i < cursor + 7u)
        return le32_byte(disp, byte_i - cursor - 3u);
    return 0u;
}

uint store_local_index_r32_byte(uint slot, uint index, uint src, uint byte_i)
{
    bool rex = needs_rex_sib(src, index, 4u);
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_sib(src, index, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x89u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x44u : 0x84u) | ((src & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x84u | ((index & 7u) << 3u);
    if (disp8 && byte_i == cursor + 3u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 3u && byte_i < cursor + 7u)
        return le32_byte(disp, byte_i - cursor - 3u);
    return 0u;
}

uint store_param_index_slot_r32_byte(uint base, uint index, uint src, uint ordinal, uint byte_i)
{
    bool rex = needs_rex_sib(src, index, base);
    uint disp = ordinal * 4u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_sib(src, index, base);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x89u;
    if (byte_i == cursor + 1u) return 0x44u | ((src & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x80u | ((index & 7u) << 3u) | (base & 7u);
    if (byte_i == cursor + 3u) return disp & 0xffu;
    return 0u;
}

uint store_param_index_r32_byte(uint base, uint index, uint src, uint byte_i)
{
    return store_param_index_slot_r32_byte(base, index, src, 0u, byte_i);
}

uint store_local_imm32_byte(uint slot, uint imm, uint byte_i)
{
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    if (byte_i == 0u) return 0xc7u;
    if (byte_i == 1u) return disp8 ? 0x44u : 0x84u;
    if (byte_i == 2u) return 0x24u;
    if (disp8 && byte_i == 3u) return disp & 0xffu;
    if (disp8 && byte_i < 8u) return le32_byte(imm, byte_i - 4u);
    if (!disp8 && byte_i >= 3u && byte_i < 7u) return le32_byte(disp, byte_i - 3u);
    if (!disp8 && byte_i < 11u) return le32_byte(imm, byte_i - 7u);
    return 0u;
}

uint store_local_zero_byte(uint slot, uint byte_i)
{
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    if (byte_i == 0u) return 0x83u;
    if (byte_i == 1u) return disp8 ? 0x64u : 0xa4u;
    if (byte_i == 2u) return 0x24u;
    if (disp8 && byte_i == 3u) return disp & 0xffu;
    if (disp8 && byte_i == 4u) return 0u;
    if (!disp8 && byte_i >= 3u && byte_i < 7u) return le32_byte(disp, byte_i - 3u);
    if (!disp8 && byte_i == 7u) return 0u;
    return 0u;
}

uint cmp_local_imm32_byte(uint slot, uint imm, uint byte_i)
{
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    if (byte_i == 0u) return 0x81u;
    if (byte_i == 1u) return disp8 ? 0x7cu : 0xbcu;
    if (byte_i == 2u) return 0x24u;
    if (disp8 && byte_i == 3u) return disp & 0xffu;
    if (disp8 && byte_i < 8u) return le32_byte(imm, byte_i - 4u);
    if (!disp8 && byte_i >= 3u && byte_i < 7u) return le32_byte(disp, byte_i - 3u);
    if (!disp8 && byte_i < 11u) return le32_byte(imm, byte_i - 7u);
    return 0u;
}

uint cmp_local_imm_byte(uint slot, uint imm, uint byte_i)
{
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    bool imm8 = signed_i8_immediate(imm);
    if (byte_i == 0u) return imm8 ? 0x83u : 0x81u;
    if (byte_i == 1u) return disp8 ? 0x7cu : 0xbcu;
    if (byte_i == 2u) return 0x24u;
    if (disp8 && byte_i == 3u) return disp & 0xffu;
    if (disp8 && imm8 && byte_i == 4u) return imm & 0xffu;
    if (disp8 && !imm8 && byte_i < 8u) return le32_byte(imm, byte_i - 4u);
    if (!disp8 && byte_i >= 3u && byte_i < 7u) return le32_byte(disp, byte_i - 3u);
    if (!disp8 && imm8 && byte_i == 7u) return imm & 0xffu;
    if (!disp8 && !imm8 && byte_i < 11u) return le32_byte(imm, byte_i - 7u);
    return 0u;
}

uint cmp_local_r32_size(uint slot, uint reg)
{
    return local_mem_r32_size(reg, slot);
}

uint cmp_local_r32_byte(uint slot, uint reg, uint byte_i)
{
    bool rex = needs_rex_modrm(reg, 4u);
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(reg, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x39u;
    if (byte_i == cursor + 1u) return (disp8 ? 0x44u : 0x84u) | ((reg & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x24u;
    if (disp8 && byte_i == cursor + 3u) return disp & 0xffu;
    if (!disp8 && byte_i >= cursor + 3u && byte_i < cursor + 7u)
        return le32_byte(disp, byte_i - cursor - 3u);
    return 0u;
}

uint add_local_imm8_byte(uint slot, uint imm, uint byte_i)
{
    uint disp = local_slot_disp(slot);
    bool disp8 = disp <= 127u;
    if (byte_i == 0u) return 0x83u;
    if (byte_i == 1u) return disp8 ? 0x44u : 0x84u;
    if (byte_i == 2u) return 0x24u;
    if (disp8 && byte_i == 3u) return disp & 0xffu;
    if (disp8 && byte_i == 4u) return imm & 0xffu;
    if (!disp8 && byte_i >= 3u && byte_i < 7u) return le32_byte(disp, byte_i - 3u);
    if (!disp8 && byte_i == 7u) return imm & 0xffu;
    return 0u;
}

uint jge_target_from_byte(uint source_next, uint target, uint byte_i)
{
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x8du;
    if (byte_i < 6u) return 0u;
    return 0u;
}

uint for_array_branch_byte(uint inst_i, uint index_slot, uint len, uint target, uint byte_i)
{
    uint cmp_size = cmp_local_imm_size(index_slot, len);
    if (byte_i < cmp_size)
        return cmp_local_imm_byte(index_slot, len, byte_i);
    return jge_target_from_byte(
        x86_inst_byte_offset[inst_i] + cmp_size + 6u,
        target,
        byte_i - cmp_size);
}

uint param_aggregate_payload_base(uint payload)
{
    return unpack_u16_pair_low(payload);
}

uint param_aggregate_payload_ordinal(uint payload)
{
    return unpack_u16_pair_high(payload);
}

uint match_tag_branch_byte(uint inst_i, uint packed_source, uint payload, uint target, uint byte_i)
{
    uint source_kind = unpack_u16_pair_low(packed_source);
    uint tag = unpack_u16_pair_high(packed_source);
    uint cmp_size = 0u;
    if (source_kind == X86_AGG_SOURCE_LOCAL)
    {
        cmp_size = cmp_local_imm_size(payload, tag);
        if (byte_i < cmp_size)
            return cmp_local_imm_byte(payload, tag, byte_i);
    }
    else if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint payload_base = param_aggregate_payload_base(payload);
        uint payload_ordinal = param_aggregate_payload_ordinal(payload);
        cmp_size = cmp_ptr_slot_imm_size(payload_base, payload_ordinal, tag);
        if (byte_i < cmp_size)
            return cmp_ptr_slot_imm_byte(payload_base, payload_ordinal, tag, byte_i);
    }
    else
    {
        return 0u;
    }
    return jne_target_from_byte(
        x86_inst_byte_offset[inst_i] + cmp_size + 6u,
        target,
        byte_i - cmp_size);
}

uint for_array_load_byte(uint array_base_slot, uint index_slot, uint value_slot, uint byte_i)
{
    uint load_index_size = local_mem_r32_size(X86_REG_R11D, index_slot);
    uint load_value_size = local_slot_disp(array_base_slot) <= 127u
                               ? 4u + (needs_rex_sib(X86_REG_R11D, X86_REG_R11D, 4u) ? 1u : 0u)
                               : 7u + (needs_rex_sib(X86_REG_R11D, X86_REG_R11D, 4u) ? 1u : 0u);
    if (byte_i < load_index_size)
        return load_local_r32_byte(X86_REG_R11D, index_slot, byte_i);
    if (byte_i < load_index_size + load_value_size)
        return load_local_index_r32_byte(
            X86_REG_R11D,
            array_base_slot,
            X86_REG_R11D,
            byte_i - load_index_size);
    return store_local_r32_byte(value_slot, X86_REG_R11D, byte_i - load_index_size - load_value_size);
}

uint for_param_array_load_byte(uint packed_base, uint index_slot, uint value_slot, uint byte_i)
{
    uint array_base_reg = unpack_u16_pair_low(packed_base);
    uint ordinal = unpack_u16_pair_high(packed_base);
    uint load_index_size = local_mem_r32_size(X86_REG_R11D, index_slot);
    uint load_value_size = param_index_slot_mem_r32_size(
        X86_REG_R11D,
        array_base_reg,
        X86_REG_R11D,
        ordinal);
    if (byte_i < load_index_size)
        return load_local_r32_byte(X86_REG_R11D, index_slot, byte_i);
    if (byte_i < load_index_size + load_value_size)
        return load_param_index_slot_r32_byte(
            X86_REG_R11D,
            array_base_reg,
            X86_REG_R11D,
            ordinal,
            byte_i - load_index_size);
    return store_local_r32_byte(value_slot, X86_REG_R11D, byte_i - load_index_size - load_value_size);
}

uint for_array_inc_jmp_byte(uint inst_i, uint index_slot, uint target, uint stride, uint byte_i)
{
    if (stride == 0u)
        stride = 1u;
    uint add_size = local_slot_disp(index_slot) <= 127u ? 5u : 8u;
    if (byte_i < add_size)
        return add_local_imm8_byte(index_slot, stride, byte_i);
    return jmp_target_from_byte(
        x86_inst_byte_offset[inst_i] + add_size + 5u,
        target,
        byte_i - add_size);
}

uint copy_local_r32_byte(uint dst_slot, uint src_slot, uint byte_i)
{
    uint load_size = local_mem_r32_size(X86_REG_R11D, src_slot);
    if (byte_i < load_size)
        return load_local_r32_byte(X86_REG_R11D, src_slot, byte_i);
    return store_local_r32_byte(dst_slot, X86_REG_R11D, byte_i - load_size);
}

uint for_interval_branch_byte(uint inst_i, uint index_slot, uint end_slot, uint target, uint byte_i)
{
    uint load_end_size = local_mem_r32_size(X86_REG_R11D, end_slot);
    uint cmp_size = cmp_local_r32_size(index_slot, X86_REG_R11D);
    if (byte_i < load_end_size)
        return load_local_r32_byte(X86_REG_R11D, end_slot, byte_i);
    byte_i -= load_end_size;
    if (byte_i < cmp_size)
        return cmp_local_r32_byte(index_slot, X86_REG_R11D, byte_i);
    return jge_target_from_byte(
        x86_inst_byte_offset[inst_i] + load_end_size + cmp_size + 6u,
        target,
        byte_i - cmp_size);
}

uint sub_r64_rsp_imm32_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x48u;
    if (byte_i == 1u) return 0x81u;
    if (byte_i == 2u) return 0xecu;
    if (byte_i < 7u) return le32_byte(imm, byte_i - 3u);
    return 0u;
}

uint sub_r64_rsp_imm8_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x48u;
    if (byte_i == 1u) return 0x83u;
    if (byte_i == 2u) return 0xecu;
    if (byte_i == 3u) return imm & 0xffu;
    return 0u;
}

uint add_r64_rsp_imm32_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x48u;
    if (byte_i == 1u) return 0x81u;
    if (byte_i == 2u) return 0xc4u;
    if (byte_i < 7u) return le32_byte(imm, byte_i - 3u);
    return 0u;
}

uint add_r64_rsp_imm8_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x48u;
    if (byte_i == 1u) return 0x83u;
    if (byte_i == 2u) return 0xc4u;
    if (byte_i == 3u) return imm & 0xffu;
    return 0u;
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

uint process_stack_save_byte(uint byte_i)
{
    if (byte_i == 0u) return 0x49u;
    if (byte_i == 1u) return 0x89u;
    if (byte_i == 2u) return 0xe7u;
    return 0u;
}

uint sub_r64_rsp_frame_byte(uint frame_size, uint byte_i)
{
    return frame_size <= 127u ? sub_r64_rsp_imm8_byte(frame_size, byte_i)
                              : sub_r64_rsp_imm32_byte(frame_size, byte_i);
}

uint add_r64_rsp_frame_byte(uint frame_size, uint byte_i)
{
    return frame_size <= 127u ? add_r64_rsp_imm8_byte(frame_size, byte_i)
                              : add_r64_rsp_imm32_byte(frame_size, byte_i);
}

uint entry_stack_jmp_byte(uint inst_i, uint target, uint frame_size, uint byte_i)
{
    uint save_size = process_stack_save_size();
    if (byte_i < save_size)
        return process_stack_save_byte(byte_i);
    byte_i -= save_size;

    uint adjust_size = stack_frame_adjust_size(frame_size);
    if (byte_i < adjust_size)
        return sub_r64_rsp_frame_byte(frame_size, byte_i);
    return jmp_target_byte(inst_i, target, byte_i - adjust_size);
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
    bool rex = op == X86_OP_MUL_I32 ?
               needs_rex_modrm(dst, src) :
               needs_rex_modrm(src, dst);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor)
            return op == X86_OP_MUL_I32 ?
                   rex_modrm(dst, src) :
                   rex_modrm(src, dst);
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

uint cmp_r32_r32_size(uint left, uint right)
{
    return valid_reg(left) && valid_reg(right)
               ? 2u + (needs_rex_modrm(right, left) ? 1u : 0u)
               : 0u;
}

uint cmp_r32_imm_size(uint reg, uint imm)
{
    return valid_reg(reg)
               ? (signed_i8_immediate(imm) ? 3u : 6u) + (needs_rex_modrm(7u, reg) ? 1u : 0u)
               : 0u;
}

uint cmp_r32_imm_byte(uint reg, uint imm, uint byte_i)
{
    bool rex = needs_rex_modrm(7u, reg);
    bool imm8 = signed_i8_immediate(imm);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(7u, reg);
        cursor += 1u;
    }
    if (byte_i == cursor) return imm8 ? 0x83u : 0x81u;
    if (byte_i == cursor + 1u) return 0xf8u | (reg & 7u);
    if (imm8 && byte_i == cursor + 2u) return imm & 0xffu;
    if (!imm8 && byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(imm, byte_i - cursor - 2u);
    return 0u;
}

uint packed_index_reg(uint packed)
{
    return packed & 0xffu;
}

uint packed_index_width(uint packed)
{
    return packed >> 8u;
}

uint small_exit_trap_size()
{
    return 8u;
}

uint exit_code_macro_byte(uint code, uint byte_i)
{
    uint exit_code_size = 3u;
    if (byte_i < exit_code_size)
        return mov_r32_imm_compact_byte(X86_REG_EDI, code, byte_i);
    byte_i -= exit_code_size;
    uint syscall_number_size = 3u;
    if (byte_i < syscall_number_size)
        return mov_r32_imm_compact_byte(X86_REG_EAX, 60u, byte_i);
    byte_i -= syscall_number_size;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    return 0u;
}

uint jb_skip_bytes(uint skip_bytes, uint byte_i)
{
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x82u;
    if (byte_i < 6u) return le32_byte(skip_bytes, byte_i - 2u);
    return 0u;
}

uint je_skip_bytes(uint skip_bytes, uint byte_i)
{
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x84u;
    if (byte_i < 6u) return le32_byte(skip_bytes, byte_i - 2u);
    return 0u;
}

uint jne_skip_bytes(uint skip_bytes, uint byte_i)
{
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x85u;
    if (byte_i < 6u) return le32_byte(skip_bytes, byte_i - 2u);
    return 0u;
}

uint zero_divisor_check_size(uint divisor)
{
    if (!valid_reg(divisor))
        return 0u;
    uint cmp_size = cmp_r32_imm_size(divisor, 0u);
    uint trap_size = small_exit_trap_size();
    return cmp_size != 0u ? cmp_size + 6u + trap_size : 0u;
}

uint zero_divisor_check_byte(uint divisor, uint byte_i)
{
    uint cmp_size = cmp_r32_imm_size(divisor, 0u);
    if (byte_i < cmp_size)
        return cmp_r32_imm_byte(divisor, 0u, byte_i);
    byte_i -= cmp_size;
    uint trap_size = small_exit_trap_size();
    if (byte_i < 6u)
        return jne_skip_bytes(trap_size, byte_i);
    return exit_code_macro_byte(103u, byte_i - 6u);
}

uint signed_div_overflow_check_size(uint left, uint right)
{
    if (!valid_reg(left) || !valid_reg(right))
        return 0u;
    uint right_cmp_size = cmp_r32_imm_size(right, I32_NEG_ONE);
    uint left_cmp_size = cmp_r32_imm_size(left, I32_MIN);
    uint trap_size = small_exit_trap_size();
    return right_cmp_size != 0u && left_cmp_size != 0u
               ? right_cmp_size + 6u + left_cmp_size + 6u + trap_size
               : 0u;
}

uint signed_div_overflow_check_byte(uint left, uint right, uint byte_i)
{
    uint right_cmp_size = cmp_r32_imm_size(right, I32_NEG_ONE);
    if (byte_i < right_cmp_size)
        return cmp_r32_imm_byte(right, I32_NEG_ONE, byte_i);
    byte_i -= right_cmp_size;

    uint left_cmp_size = cmp_r32_imm_size(left, I32_MIN);
    uint trap_size = small_exit_trap_size();
    uint skip_overflow_case_size = left_cmp_size + 6u + trap_size;
    if (byte_i < 6u)
        return jne_skip_bytes(skip_overflow_case_size, byte_i);
    byte_i -= 6u;

    if (byte_i < left_cmp_size)
        return cmp_r32_imm_byte(left, I32_MIN, byte_i);
    byte_i -= left_cmp_size;

    if (byte_i < 6u)
        return jne_skip_bytes(trap_size, byte_i);
    return exit_code_macro_byte(104u, byte_i - 6u);
}

uint divmod_trap_check_size(uint left, uint right)
{
    uint zero_check = zero_divisor_check_size(right);
    uint overflow_check = signed_div_overflow_check_size(left, right);
    return zero_check != 0u && overflow_check != 0u ? zero_check + overflow_check : 0u;
}

uint divmod_trap_check_byte(uint left, uint right, uint byte_i)
{
    uint zero_check = zero_divisor_check_size(right);
    if (byte_i < zero_check)
        return zero_divisor_check_byte(right, byte_i);
    return signed_div_overflow_check_byte(left, right, byte_i - zero_check);
}

uint index_bounds_check_size(uint index, uint width)
{
    if (!valid_index_reg(index) || width == 0u)
        return 0u;
    uint cmp_size = cmp_r32_imm_size(index, width);
    uint trap_size = small_exit_trap_size();
    return cmp_size != 0u ? cmp_size + 6u + trap_size : 0u;
}

uint index_bounds_check_byte(uint index, uint width, uint byte_i)
{
    uint cmp_size = cmp_r32_imm_size(index, width);
    if (byte_i < cmp_size)
        return cmp_r32_imm_byte(index, width, byte_i);
    byte_i -= cmp_size;
    uint trap_size = small_exit_trap_size();
    if (byte_i < 6u)
        return jb_skip_bytes(trap_size, byte_i);
    return exit_code_macro_byte(101u, byte_i - 6u);
}

uint shift_count_check_size(uint count)
{
    if (!valid_reg(count))
        return 0u;
    uint cmp_size = cmp_r32_imm_size(count, 32u);
    uint trap_size = small_exit_trap_size();
    return cmp_size != 0u ? cmp_size + 6u + trap_size : 0u;
}

uint shift_count_check_byte(uint count, uint byte_i)
{
    uint cmp_size = cmp_r32_imm_size(count, 32u);
    if (byte_i < cmp_size)
        return cmp_r32_imm_byte(count, 32u, byte_i);
    byte_i -= cmp_size;
    uint trap_size = small_exit_trap_size();
    if (byte_i < 6u)
        return jb_skip_bytes(trap_size, byte_i);
    return exit_code_macro_byte(102u, byte_i - 6u);
}

uint checked_load_local_index_r32_byte(uint dst, uint slot, uint packed, uint byte_i)
{
    uint index = packed_index_reg(packed);
    uint width = packed_index_width(packed);
    uint check_size = index_bounds_check_size(index, width);
    if (byte_i < check_size)
        return index_bounds_check_byte(index, width, byte_i);
    return load_local_index_r32_byte(dst, slot, index, byte_i - check_size);
}

uint checked_store_local_index_r32_byte(uint slot, uint packed, uint src, uint byte_i)
{
    uint index = packed_index_reg(packed);
    uint width = packed_index_width(packed);
    uint check_size = index_bounds_check_size(index, width);
    if (byte_i < check_size)
        return index_bounds_check_byte(index, width, byte_i);
    return store_local_index_r32_byte(slot, index, src, byte_i - check_size);
}

uint checked_load_param_index_r32_byte(uint dst, uint base, uint packed, uint byte_i)
{
    uint payload_base = param_aggregate_payload_base(base);
    uint payload_ordinal = param_aggregate_payload_ordinal(base);
    uint index = packed_index_reg(packed);
    uint width = packed_index_width(packed);
    uint check_size = index_bounds_check_size(index, width);
    if (byte_i < check_size)
        return index_bounds_check_byte(index, width, byte_i);
    return load_param_index_slot_r32_byte(dst, payload_base, index, payload_ordinal, byte_i - check_size);
}

uint checked_store_param_index_r32_byte(uint base, uint packed, uint src, uint byte_i)
{
    uint payload_base = param_aggregate_payload_base(base);
    uint payload_ordinal = param_aggregate_payload_ordinal(base);
    uint index = packed_index_reg(packed);
    uint width = packed_index_width(packed);
    uint check_size = index_bounds_check_size(index, width);
    if (byte_i < check_size)
        return index_bounds_check_byte(index, width, byte_i);
    return store_param_index_slot_r32_byte(payload_base, index, src, payload_ordinal, byte_i - check_size);
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
    uint field = op == X86_OP_SHL_I32 ? 4u
               : op == X86_OP_SHR_U32 ? 5u
               : 7u;
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
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x84u;
    if (byte_i < 6u) return 0u;
    return 0u;
}

uint jne_target_from_byte(uint source_next, uint target, uint byte_i)
{
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x85u;
    if (byte_i < 6u) return 0u;
    return 0u;
}

uint jmp_target_byte(uint inst_i, uint target, uint byte_i)
{
    if (byte_i == 0u) return 0xe9u;
    if (byte_i < 5u) return 0u;
    return 0u;
}

uint jmp_target_from_byte(uint source_next, uint target, uint byte_i)
{
    if (byte_i == 0u) return 0xe9u;
    if (byte_i < 5u) return 0u;
    return 0u;
}

uint call_target_byte(uint inst_i, uint target, uint byte_i)
{
    if (byte_i == 0u) return 0xe8u;
    if (byte_i < 5u) return 0u;
    return 0u;
}

uint call_target_from_byte(uint source_next, uint target, uint byte_i)
{
    if (byte_i == 0u) return 0xe8u;
    if (byte_i < 5u) return 0u;
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

uint xor_r32_imm32_size(uint dst)
{
    return valid_reg(dst) ? 6u + (needs_rex_modrm(6u, dst) ? 1u : 0u) : 0u;
}

uint xor_r32_self_size(uint reg)
{
    return valid_reg(reg) ? 2u + (needs_rex_modrm(reg, reg) ? 1u : 0u) : 0u;
}

uint movd_xmm_r32_size(uint src)
{
    return valid_reg(src) ? 4u + (needs_rex_modrm(0u, src) ? 1u : 0u) : 0u;
}

uint movd_r32_xmm_size(uint dst)
{
    return valid_reg(dst) ? 4u + (needs_rex_modrm(0u, dst) ? 1u : 0u) : 0u;
}

bool f32_binary_op(uint op)
{
    return op == X86_OP_ADD_F32 ||
           op == X86_OP_SUB_F32 ||
           op == X86_OP_MUL_F32 ||
           op == X86_OP_DIV_F32;
}

uint f32_binary_opcode(uint op)
{
    if (op == X86_OP_ADD_F32) return 0x58u;
    if (op == X86_OP_SUB_F32) return 0x5cu;
    if (op == X86_OP_MUL_F32) return 0x59u;
    if (op == X86_OP_DIV_F32) return 0x5eu;
    return 0u;
}

uint xor_r32_imm32_byte(uint dst, uint imm, uint byte_i)
{
    bool rex = needs_rex_modrm(6u, dst);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(6u, dst);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x81u;
    if (byte_i == cursor + 1u) return modrm(6u, dst);
    if (byte_i >= cursor + 2u && byte_i < cursor + 6u)
        return le32_byte(imm, byte_i - cursor - 2u);
    return 0u;
}

uint movd_xmm_r32_byte(uint xmm, uint src, uint byte_i)
{
    bool rex = needs_rex_modrm(xmm, src);
    uint cursor = 0u;
    if (byte_i == cursor) return 0x66u;
    cursor += 1u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(xmm, src);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return 0x6eu;
    if (byte_i == cursor + 2u) return modrm(xmm, src);
    return 0u;
}

uint movd_r32_xmm_byte(uint dst, uint xmm, uint byte_i)
{
    bool rex = needs_rex_modrm(xmm, dst);
    uint cursor = 0u;
    if (byte_i == cursor) return 0x66u;
    cursor += 1u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(xmm, dst);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return 0x7eu;
    if (byte_i == cursor + 2u) return modrm(xmm, dst);
    return 0u;
}

uint f32_binary_op_byte(uint op, uint dst_xmm, uint src_xmm, uint byte_i)
{
    bool rex = needs_rex_modrm(dst_xmm, src_xmm);
    uint cursor = 0u;
    if (byte_i == cursor) return 0xf3u;
    cursor += 1u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst_xmm, src_xmm);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return f32_binary_opcode(op);
    if (byte_i == cursor + 2u) return modrm(dst_xmm, src_xmm);
    return 0u;
}

uint cvtsi2ss_xmm_r32_byte(uint xmm, uint src, uint byte_i)
{
    bool rex = needs_rex_modrm(xmm, src);
    uint cursor = 0u;
    if (byte_i == cursor) return 0xf3u;
    cursor += 1u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(xmm, src);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return 0x2au;
    if (byte_i == cursor + 2u) return modrm(xmm, src);
    return 0u;
}

uint ucomiss_xmm_xmm_byte(uint left_xmm, uint right_xmm, uint byte_i)
{
    bool rex = needs_rex_modrm(left_xmm, right_xmm);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(left_xmm, right_xmm);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x0fu;
    if (byte_i == cursor + 1u) return 0x2eu;
    if (byte_i == cursor + 2u) return modrm(left_xmm, right_xmm);
    return 0u;
}

uint mov_r32_imm_compact_size(uint dst, uint imm)
{
    if (!valid_reg(dst))
        return 0u;
    if (imm == 0u)
        return xor_r32_self_size(dst);
    if (dst != X86_REG_ESP && signed_i8_immediate(imm))
        return 3u + (needs_rex_opcode_reg(dst) ? 1u : 0u);
    return mov_r32_imm32_size(dst);
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
    if (op == X86_OP_NEG_F32)
    {
        uint move_size = dst == src ? 0u : mov_r32_r32_size(dst, src);
        if (byte_i < move_size)
            return mov_r32_r32_byte(dst, src, byte_i);
        byte_i -= move_size;
        return xor_r32_imm32_byte(dst, 0x80000000u, byte_i);
    }
    if (op == X86_OP_I32_TO_F32)
    {
        uint convert_size = 4u + (needs_rex_modrm(0u, src) ? 1u : 0u);
        if (byte_i < convert_size)
            return cvtsi2ss_xmm_r32_byte(0u, src, byte_i);
        byte_i -= convert_size;
        return movd_r32_xmm_byte(dst, 0u, byte_i);
    }
    return 0u;
}

uint binary_macro_byte(uint op, uint dst, uint packed, uint byte_i)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    if (op == X86_OP_DIV_I32 || op == X86_OP_MOD_I32 ||
        op == X86_OP_DIV_U32 || op == X86_OP_MOD_U32)
    {
        bool unsigned_op = op == X86_OP_DIV_U32 || op == X86_OP_MOD_U32;
        uint check_size = unsigned_op
                              ? zero_divisor_check_size(right)
                              : divmod_trap_check_size(left, right);
        if (byte_i < check_size)
        {
            return unsigned_op
                       ? zero_divisor_check_byte(right, byte_i)
                       : divmod_trap_check_byte(left, right, byte_i);
        }
        byte_i -= check_size;

        uint right_move_size = right == X86_REG_ECX ? 0u : mov_r32_r32_size(X86_REG_ECX, right);
        if (byte_i < right_move_size)
            return mov_r32_r32_byte(X86_REG_ECX, right, byte_i);
        byte_i -= right_move_size;

        uint left_move_size = left == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, left);
        if (byte_i < left_move_size)
            return mov_r32_r32_byte(X86_REG_EAX, left, byte_i);
        byte_i -= left_move_size;

        uint extend_size = unsigned_op ? xor_r32_self_size(X86_REG_EDX) : 1u;
        if (byte_i < extend_size)
        {
            return unsigned_op
                       ? xor_r32_r32_byte(X86_REG_EDX, byte_i)
                       : (byte_i == 0u ? 0x99u : 0u);
        }
        byte_i -= extend_size;

        uint div_size = 2u + (needs_rex_modrm(unsigned_op ? 6u : 7u, X86_REG_ECX) ? 1u : 0u);
        if (byte_i < div_size)
            return unsigned_op
                       ? div_r32_byte(X86_REG_ECX, byte_i)
                       : idiv_r32_byte(X86_REG_ECX, byte_i);
        byte_i -= div_size;

        uint result = (op == X86_OP_MOD_I32 || op == X86_OP_MOD_U32) ? X86_REG_EDX : X86_REG_EAX;
        return dst == result ? 0u : mov_r32_r32_byte(dst, result, byte_i);
    }

    if (op == X86_OP_SHL_I32 || op == X86_OP_SHR_I32 || op == X86_OP_SHR_U32)
    {
        uint check_size = shift_count_check_size(right);
        if (byte_i < check_size)
            return shift_count_check_byte(right, byte_i);
        byte_i -= check_size;

        uint move_size = dst == left ? 0u : mov_r32_r32_size(dst, left);
        if (byte_i < move_size)
            return mov_r32_r32_byte(dst, left, byte_i);
        byte_i -= move_size;

        uint count_move_size = right == X86_REG_ECX ? 0u : mov_r32_r32_size(X86_REG_ECX, right);
        if (byte_i < count_move_size)
            return mov_r32_r32_byte(X86_REG_ECX, right, byte_i);
        byte_i -= count_move_size;
        return shift_r32_cl_byte(op, dst, byte_i);
    }

    if (f32_binary_op(op))
    {
        uint left_load_size = movd_xmm_r32_size(left);
        if (byte_i < left_load_size)
            return movd_xmm_r32_byte(0u, left, byte_i);
        byte_i -= left_load_size;

        uint right_load_size = movd_xmm_r32_size(right);
        if (byte_i < right_load_size)
            return movd_xmm_r32_byte(1u, right, byte_i);
        byte_i -= right_load_size;

        uint op_size = 4u;
        if (byte_i < op_size)
            return f32_binary_op_byte(op, 0u, 1u, byte_i);
        byte_i -= op_size;

        return movd_r32_xmm_byte(dst, 0u, byte_i);
    }

    uint move_size = dst == left ? 0u : mov_r32_r32_size(dst, left);
    if (byte_i < move_size)
        return mov_r32_r32_byte(dst, left, byte_i);
    byte_i -= move_size;

    return alu_r32_r32_byte(op, dst, right, byte_i);
}

uint compare_macro_byte(uint compare_op, uint dst, uint packed, uint byte_i)
{
    uint left = packed_reg_a(packed);
    uint right = packed_reg_b(packed);
    if ((compare_op & X86_CMP_FLOAT_FLAG) != 0u)
    {
        uint left_load_size = movd_xmm_r32_size(left);
        if (byte_i < left_load_size)
            return movd_xmm_r32_byte(0u, left, byte_i);
        byte_i -= left_load_size;

        uint right_load_size = movd_xmm_r32_size(right);
        if (byte_i < right_load_size)
            return movd_xmm_r32_byte(1u, right, byte_i);
        byte_i -= right_load_size;

        uint cmp_size = 3u;
        if (byte_i < cmp_size)
            return ucomiss_xmm_xmm_byte(0u, 1u, byte_i);
        byte_i -= cmp_size;

        uint set_size = 3u + (needs_rex_low8_modrm(0u, dst) ? 1u : 0u);
        if (byte_i < set_size)
            return setcc_r8_byte(compare_op, dst, byte_i);
        byte_i -= set_size;
        return movzx_r32_r8_byte(dst, byte_i);
    }

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
    uint syscall_number_size = mov_r32_imm_compact_size(X86_REG_EAX, 60u);
    if (byte_i < syscall_number_size)
        return mov_r32_imm_compact_byte(X86_REG_EAX, 60u, byte_i);
    byte_i -= syscall_number_size;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    return 0u;
}

uint exit_zero_macro_byte(uint byte_i)
{
    uint exit_code_size = mov_r32_imm_compact_size(X86_REG_EDI, 0u);
    if (byte_i < exit_code_size)
        return mov_r32_imm_compact_byte(X86_REG_EDI, 0u, byte_i);
    byte_i -= exit_code_size;
    uint syscall_number_size = mov_r32_imm_compact_size(X86_REG_EAX, 60u);
    if (byte_i < syscall_number_size)
        return mov_r32_imm_compact_byte(X86_REG_EAX, 60u, byte_i);
    byte_i -= syscall_number_size;
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

uint saved_call_reg_disp(uint slot, uint save_mask)
{
    uint above_mask = slot < 7u ? (0xffu << (slot + 1u)) : 0u;
    return countbits(save_mask & above_mask) * 8u;
}

uint load_saved_call_reg_r32_size(uint dst, uint src, uint save_mask)
{
    uint slot = 0xffffffffu;
    if (!valid_reg(dst) || !call_saved_reg_slot(src, slot) ||
        !call_save_mask_has_slot(save_mask, slot))
        return 0u;
    return 4u + (needs_rex_modrm(dst, 4u) ? 1u : 0u);
}

uint load_saved_call_reg_r64_size(uint dst, uint src, uint save_mask)
{
    uint slot = 0xffffffffu;
    if (!valid_reg(dst) || !call_saved_reg_slot(src, slot) ||
        !call_save_mask_has_slot(save_mask, slot))
        return 0u;
    return 5u;
}

uint load_saved_call_reg_r32_byte(uint dst, uint src, uint save_mask, uint byte_i)
{
    uint slot = 0xffffffffu;
    if (!call_saved_reg_slot(src, slot) || !call_save_mask_has_slot(save_mask, slot))
        return 0u;
    bool rex = needs_rex_modrm(dst, 4u);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst, 4u);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return 0x44u | ((dst & 7u) << 3u);
    if (byte_i == cursor + 2u) return 0x24u;
    if (byte_i == cursor + 3u) return saved_call_reg_disp(slot, save_mask) & 0xffu;
    return 0u;
}

uint load_saved_call_reg_r64_byte(uint dst, uint src, uint save_mask, uint byte_i)
{
    uint slot = 0xffffffffu;
    if (!call_saved_reg_slot(src, slot) || !call_save_mask_has_slot(save_mask, slot))
        return 0u;
    if (byte_i == 0u) return rex64_modrm(dst, 4u);
    if (byte_i == 1u) return 0x8bu;
    if (byte_i == 2u) return 0x44u | ((dst & 7u) << 3u);
    if (byte_i == 3u) return 0x24u;
    if (byte_i == 4u) return saved_call_reg_disp(slot, save_mask) & 0xffu;
    return 0u;
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

uint print_saved_reg_disp(uint slot)
{
    return 80u - slot * 8u;
}

uint load_print_saved_reg_r32_size(uint dst, uint src)
{
    uint slot = 0xffffffffu;
    return valid_reg(dst) && print_saved_reg_slot(src, slot)
               ? 4u + (needs_rex_modrm(dst, 4u) ? 1u : 0u)
               : 0u;
}

uint load_print_saved_reg_r32_byte(uint dst, uint src, uint byte_i)
{
    uint slot = 0xffffffffu;
    if (!print_saved_reg_slot(src, slot))
        return 0u;
    return load_rsp_disp8_r32_byte(dst, print_saved_reg_disp(slot), byte_i);
}

uint host_arg_source_r32_size(uint dst, uint src)
{
    uint slot = 0xffffffffu;
    if (print_saved_reg_slot(src, slot))
        return load_print_saved_reg_r32_size(dst, src);
    return valid_reg(dst) && valid_reg(src) ? mov_r32_r32_size(dst, src) : 0u;
}

uint host_arg_source_r32_byte(uint dst, uint src, uint byte_i)
{
    uint slot = 0xffffffffu;
    if (print_saved_reg_slot(src, slot))
        return load_print_saved_reg_r32_byte(dst, src, byte_i);
    return mov_r32_r32_byte(dst, src, byte_i);
}

uint call_save_slot_start(uint save_mask, uint slot)
{
    uint below_mask = slot == 0u ? 0u : ((1u << slot) - 1u);
    uint below = save_mask & below_mask & 0xffu;
    return countbits(below) + countbits(below & 0xf0u);
}

uint call_restore_slot_start(uint save_mask, uint slot)
{
    uint above_mask = slot < 7u ? (0xffu << (slot + 1u)) : 0u;
    uint above = save_mask & above_mask & 0xffu;
    return countbits(above) + countbits(above & 0xf0u);
}

bool call_save_slot_byte(uint save_mask, uint slot, uint byte_i, out uint byte)
{
    byte = 0u;
    if (!call_save_mask_has_slot(save_mask, slot))
        return false;
    uint reg = call_saved_reg_for_slot(slot);
    uint start = call_save_slot_start(save_mask, slot);
    uint size = push_pop_reg_size(reg);
    if (byte_i < start || byte_i >= start + size)
        return false;
    byte = push_r64_byte(reg, byte_i - start);
    return true;
}

bool call_restore_slot_byte(uint save_mask, uint slot, uint byte_i, out uint byte)
{
    byte = 0u;
    if (!call_save_mask_has_slot(save_mask, slot))
        return false;
    uint reg = call_saved_reg_for_slot(slot);
    uint start = call_restore_slot_start(save_mask, slot);
    uint size = push_pop_reg_size(reg);
    if (byte_i < start || byte_i >= start + size)
        return false;
    byte = pop_r64_byte(reg, byte_i - start);
    return true;
}

uint call_save_regs_byte(uint save_mask, uint byte_i)
{
    uint byte;
    if (call_save_slot_byte(save_mask, 0u, byte_i, byte)) return byte;
    if (call_save_slot_byte(save_mask, 1u, byte_i, byte)) return byte;
    if (call_save_slot_byte(save_mask, 2u, byte_i, byte)) return byte;
    if (call_save_slot_byte(save_mask, 3u, byte_i, byte)) return byte;
    if (call_save_slot_byte(save_mask, 4u, byte_i, byte)) return byte;
    if (call_save_slot_byte(save_mask, 5u, byte_i, byte)) return byte;
    if (call_save_slot_byte(save_mask, 6u, byte_i, byte)) return byte;
    if (call_save_slot_byte(save_mask, 7u, byte_i, byte)) return byte;
    return 0u;
}

uint print_save_regs_byte(uint byte_i)
{
    if (byte_i == 0u) return push_r64_byte(X86_REG_EAX, 0u);
    if (byte_i == 1u) return push_r64_byte(X86_REG_ECX, 0u);
    if (byte_i == 2u) return push_r64_byte(X86_REG_EDX, 0u);
    if (byte_i == 3u) return push_r64_byte(X86_REG_ESI, 0u);
    if (byte_i == 4u) return push_r64_byte(X86_REG_EDI, 0u);
    if (byte_i == 5u) return push_r64_byte(X86_REG_R8D, 0u);
    if (byte_i == 6u) return push_r64_byte(X86_REG_R8D, 1u);
    if (byte_i == 7u) return push_r64_byte(X86_REG_R9D, 0u);
    if (byte_i == 8u) return push_r64_byte(X86_REG_R9D, 1u);
    if (byte_i == 9u) return push_r64_byte(X86_REG_R10D, 0u);
    if (byte_i == 10u) return push_r64_byte(X86_REG_R10D, 1u);
    if (byte_i == 11u) return push_r64_byte(X86_REG_R11D, 0u);
    if (byte_i == 12u) return push_r64_byte(X86_REG_R11D, 1u);
    return 0u;
}

uint print_restore_regs_byte(uint byte_i)
{
    if (byte_i == 0u) return pop_r64_byte(X86_REG_R11D, 0u);
    if (byte_i == 1u) return pop_r64_byte(X86_REG_R11D, 1u);
    if (byte_i == 2u) return pop_r64_byte(X86_REG_R10D, 0u);
    if (byte_i == 3u) return pop_r64_byte(X86_REG_R10D, 1u);
    if (byte_i == 4u) return pop_r64_byte(X86_REG_R9D, 0u);
    if (byte_i == 5u) return pop_r64_byte(X86_REG_R9D, 1u);
    if (byte_i == 6u) return pop_r64_byte(X86_REG_R8D, 0u);
    if (byte_i == 7u) return pop_r64_byte(X86_REG_R8D, 1u);
    if (byte_i == 8u) return pop_r64_byte(X86_REG_EDI, 0u);
    if (byte_i == 9u) return pop_r64_byte(X86_REG_ESI, 0u);
    if (byte_i == 10u) return pop_r64_byte(X86_REG_EDX, 0u);
    if (byte_i == 11u) return pop_r64_byte(X86_REG_ECX, 0u);
    if (byte_i == 12u) return pop_r64_byte(X86_REG_EAX, 0u);
    return 0u;
}

uint call_restore_regs_byte(uint save_mask, uint byte_i)
{
    uint byte;
    if (call_restore_slot_byte(save_mask, 7u, byte_i, byte)) return byte;
    if (call_restore_slot_byte(save_mask, 6u, byte_i, byte)) return byte;
    if (call_restore_slot_byte(save_mask, 5u, byte_i, byte)) return byte;
    if (call_restore_slot_byte(save_mask, 4u, byte_i, byte)) return byte;
    if (call_restore_slot_byte(save_mask, 3u, byte_i, byte)) return byte;
    if (call_restore_slot_byte(save_mask, 2u, byte_i, byte)) return byte;
    if (call_restore_slot_byte(save_mask, 1u, byte_i, byte)) return byte;
    if (call_restore_slot_byte(save_mask, 0u, byte_i, byte)) return byte;
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
    return payload_base + ordinal / 3u;
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

uint mov_r64_r64_size(uint dst, uint src)
{
    return 3u;
}

uint lea_arg_local_ptr_size(uint target, uint slot, uint stack_adjust)
{
    uint disp = stack_adjust + local_slot_disp(slot);
    return disp <= 127u ? 5u : 8u;
}

uint lea_arg_param_ptr_size(uint target, uint payload)
{
    uint ordinal = param_aggregate_payload_ordinal(payload);
    uint disp = ordinal * 4u;
    return disp <= 127u ? 4u : 7u;
}

uint mixed_arg_move_size(uint target, uint kind, uint payload, uint save_mask, uint stack_adjust)
{
    if (kind == X86_ARG_SCALAR)
    {
        if (payload == target)
            return 0u;
        uint saved_load_size = load_saved_call_reg_r32_size(target, payload, save_mask);
        return saved_load_size != 0u ? saved_load_size : mov_r32_r32_size(target, payload);
    }
    if (kind == X86_ARG_LOCAL_PTR)
        return lea_arg_local_ptr_size(target, payload, stack_adjust);
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

uint mixed_arg_move_byte(uint target, uint kind, uint payload, uint save_mask, uint frame_adjust, uint byte_i)
{
    if (kind == X86_ARG_SCALAR)
    {
        if (payload == target)
            return 0u;
        uint saved_load_size = load_saved_call_reg_r32_size(target, payload, save_mask);
        return saved_load_size != 0u ? load_saved_call_reg_r32_byte(target, payload, save_mask, byte_i)
                                    : mov_r32_r32_byte(target, payload, byte_i);
    }
    if (kind == X86_ARG_LOCAL_PTR)
        return lea_r64_rsp_byte(target, frame_adjust + local_slot_disp(payload), byte_i);
    if (kind == X86_ARG_PARAM_PTR)
    {
        uint base = param_aggregate_payload_base(payload);
        uint ordinal = param_aggregate_payload_ordinal(payload);
        uint saved_load_size = load_saved_call_reg_r64_size(target, base, save_mask);
        if (saved_load_size != 0u)
        {
            if (byte_i < saved_load_size)
                return load_saved_call_reg_r64_byte(target, base, save_mask, byte_i);
            byte_i -= saved_load_size;
            return ordinal == 0u ? 0u : lea_r64_base_byte(target, target, ordinal * 4u, byte_i);
        }
        if (ordinal == 0u)
            return base == target ? 0u : mov_r64_r64_byte(target, base, byte_i);
        return lea_r64_base_byte(target, base, ordinal * 4u, byte_i);
    }
    return 0u;
}

bool call_mixed_arg_byte(
    uint info,
    uint packed,
    uint save_mask,
    uint save_stack,
    uint ordinal,
    uint arg_count,
    bool aggregate_return,
    inout uint byte_i,
    out uint byte)
{
    byte = 0u;
    if (ordinal >= arg_count)
        return false;
    uint target_reg = mixed_target_reg(ordinal, aggregate_return);
    uint payload = selected_mixed_arg_payload(info, packed, ordinal);
    uint kind = selected_mixed_arg_kind(info, packed, ordinal);
    uint move_size = mixed_arg_move_size(target_reg, kind, payload, save_mask, save_stack);
    if (byte_i < move_size)
    {
        byte = mixed_arg_move_byte(target_reg, kind, payload, save_mask, save_stack, byte_i);
        return true;
    }
    byte_i -= move_size;
    return false;
}

uint call_mixed_macro_byte(uint inst_i, uint target, uint info, uint packed, uint save_mask, uint byte_i)
{
    bool aggregate_return = (info & 1u) != 0u;
    uint dest = packed_u8_at(info, 1u);
    uint arg_count = packed_u8_at(info, 2u);
    uint save_size = call_save_restore_size(save_mask);
    uint save_stack = call_save_stack_size(save_mask);
    uint frame_size = call_frame_size(save_stack);
    uint frame_adjust_size = stack_frame_adjust_size(frame_size);
    if (!selected_mixed_payload_rows_valid(packed, arg_count))
        return 0u;

    if (byte_i < save_size)
        return call_save_regs_byte(save_mask, byte_i);
    byte_i -= save_size;

    uint byte;
    if (call_mixed_arg_byte(info, packed, save_mask, save_stack, 0u, arg_count, aggregate_return, byte_i, byte)) return byte;
    if (call_mixed_arg_byte(info, packed, save_mask, save_stack, 1u, arg_count, aggregate_return, byte_i, byte)) return byte;
    if (call_mixed_arg_byte(info, packed, save_mask, save_stack, 2u, arg_count, aggregate_return, byte_i, byte)) return byte;
    if (call_mixed_arg_byte(info, packed, save_mask, save_stack, 3u, arg_count, aggregate_return, byte_i, byte)) return byte;
    if (call_mixed_arg_byte(info, packed, save_mask, save_stack, 4u, arg_count, aggregate_return, byte_i, byte)) return byte;
    if (call_mixed_arg_byte(info, packed, save_mask, save_stack, 5u, arg_count, aggregate_return, byte_i, byte)) return byte;

    if (aggregate_return && dest != X86_AGG_RETURN_DEST_RET_PTR)
    {
        uint ret_ptr_size = lea_arg_local_ptr_size(X86_REG_EDI, dest, save_stack);
        if (byte_i < ret_ptr_size)
            return lea_r64_rsp_byte(X86_REG_EDI, save_stack + local_slot_disp(dest), byte_i);
        byte_i -= ret_ptr_size;
    }

    if (byte_i < frame_adjust_size)
        return sub_r64_rsp_frame_byte(frame_size, byte_i);
    byte_i -= frame_adjust_size;

    if (byte_i < 5u)
    {
        uint dest_move_size = aggregate_return || dest == X86_REG_EAX
                                  ? 0u
                                  : mov_r32_r32_size(dest, X86_REG_EAX);
        uint call_next = x86_inst_byte_offset[inst_i] + x86_inst_size[inst_i] -
                         frame_adjust_size - save_size - dest_move_size;
        return call_target_from_byte(call_next, target, byte_i);
    }
    byte_i -= 5u;

    if (byte_i < frame_adjust_size)
        return add_r64_rsp_frame_byte(frame_size, byte_i);
    byte_i -= frame_adjust_size;

    if (byte_i < save_size)
        return call_restore_regs_byte(save_mask, byte_i);
    byte_i -= save_size;

    if (aggregate_return || dest == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dest, X86_REG_EAX, byte_i);
}

uint copy_agg_ret_byte(uint source_kind, uint payload, uint ordinal, uint byte_i)
{
    uint load_size = 0u;
    if (source_kind == X86_AGG_SOURCE_LOCAL)
    {
        load_size = local_mem_r32_size(X86_REG_R11D, payload);
        if (byte_i < load_size)
            return load_local_r32_byte(X86_REG_R11D, payload, byte_i);
        byte_i -= load_size;
        return store_ptr_slot_r32_byte(X86_REG_EDI, X86_REG_R11D, ordinal, byte_i);
    }
    if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint payload_base = payload & 0x0fu;
        uint payload_ordinal = payload >> 4u;
        load_size = ptr_slot_mem_r32_size(X86_REG_R11D, payload_base, payload_ordinal);
        if (byte_i < load_size)
            return load_ptr_slot_r32_byte(X86_REG_R11D, payload_base, payload_ordinal, byte_i);
        byte_i -= load_size;
        return store_ptr_slot_r32_byte(X86_REG_EDI, X86_REG_R11D, ordinal, byte_i);
    }
    if (source_kind == X86_AGG_SOURCE_REG)
        return store_ptr_slot_r32_byte(X86_REG_EDI, payload, ordinal, byte_i);
    return 0u;
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

uint store_eax_rsp_disp8_byte(uint disp, uint byte_i)
{
    if (byte_i == 0u) return 0x89u;
    if (byte_i == 1u) return 0x44u;
    if (byte_i == 2u) return 0x24u;
    if (byte_i == 3u) return disp & 0xffu;
    return 0u;
}

uint store_eax_rsp_disp32_byte(uint disp, uint byte_i)
{
    if (byte_i == 0u) return 0x89u;
    if (byte_i == 1u) return 0x84u;
    if (byte_i == 2u) return 0x24u;
    if (byte_i >= 3u && byte_i < 7u) return le32_byte(disp, byte_i - 3u);
    return 0u;
}

uint mov_dl_m8_r8_rcx_byte(uint byte_i)
{
    if (byte_i == 0u) return 0x41u;
    if (byte_i == 1u) return 0x8au;
    if (byte_i == 2u) return 0x14u;
    if (byte_i == 3u) return 0x08u;
    return 0u;
}

uint mov_m8_rdi_rcx_dl_byte(uint byte_i)
{
    if (byte_i == 0u) return 0x88u;
    if (byte_i == 1u) return 0x14u;
    if (byte_i == 2u) return 0x0fu;
    return 0u;
}

uint mov_m8_rdi_r9_imm8_byte(uint imm, uint byte_i)
{
    if (byte_i == 0u) return 0x42u;
    if (byte_i == 1u) return 0xc6u;
    if (byte_i == 2u) return 0x04u;
    if (byte_i == 3u) return 0x0fu;
    if (byte_i == 4u) return imm & 0xffu;
    return 0u;
}

uint read_i32_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 69u;
    if (byte_i == 1u) return 49u;
    if (byte_i == 2u) return 210u;
    if (byte_i == 3u) return 69u;
    if (byte_i == 4u) return 49u;
    if (byte_i == 5u) return 201u;
    if (byte_i == 6u) return 184u;
    if (byte_i == 7u) return 0u;
    if (byte_i == 8u) return 0u;
    if (byte_i == 9u) return 0u;
    if (byte_i == 10u) return 0u;
    if (byte_i == 11u) return 68u;
    if (byte_i == 12u) return 137u;
    if (byte_i == 13u) return 199u;
    if (byte_i == 14u) return 72u;
    if (byte_i == 15u) return 141u;
    if (byte_i == 16u) return 116u;
    if (byte_i == 17u) return 36u;
    if (byte_i == 18u) return 15u;
    if (byte_i == 19u) return 186u;
    if (byte_i == 20u) return 1u;
    if (byte_i == 21u) return 0u;
    if (byte_i == 22u) return 0u;
    if (byte_i == 23u) return 0u;
    if (byte_i == 24u) return 15u;
    if (byte_i == 25u) return 5u;
    if (byte_i == 26u) return 131u;
    if (byte_i == 27u) return 248u;
    if (byte_i == 28u) return 1u;
    if (byte_i == 29u) return 117u;
    if (byte_i == 30u) return 45u;
    if (byte_i == 31u) return 15u;
    if (byte_i == 32u) return 182u;
    if (byte_i == 33u) return 22u;
    if (byte_i == 34u) return 131u;
    if (byte_i == 35u) return 250u;
    if (byte_i == 36u) return 32u;
    if (byte_i == 37u) return 126u;
    if (byte_i == 38u) return 28u;
    if (byte_i == 39u) return 131u;
    if (byte_i == 40u) return 250u;
    if (byte_i == 41u) return 48u;
    if (byte_i == 42u) return 124u;
    if (byte_i == 43u) return 40u;
    if (byte_i == 44u) return 131u;
    if (byte_i == 45u) return 250u;
    if (byte_i == 46u) return 57u;
    if (byte_i == 47u) return 127u;
    if (byte_i == 48u) return 35u;
    if (byte_i == 49u) return 69u;
    if (byte_i == 50u) return 107u;
    if (byte_i == 51u) return 210u;
    if (byte_i == 52u) return 10u;
    if (byte_i == 53u) return 131u;
    if (byte_i == 54u) return 234u;
    if (byte_i == 55u) return 48u;
    if (byte_i == 56u) return 65u;
    if (byte_i == 57u) return 1u;
    if (byte_i == 58u) return 210u;
    if (byte_i == 59u) return 65u;
    if (byte_i == 60u) return 185u;
    if (byte_i == 61u) return 1u;
    if (byte_i == 62u) return 0u;
    if (byte_i == 63u) return 0u;
    if (byte_i == 64u) return 0u;
    if (byte_i == 65u) return 235u;
    if (byte_i == 66u) return 195u;
    if (byte_i == 67u) return 69u;
    if (byte_i == 68u) return 133u;
    if (byte_i == 69u) return 201u;
    if (byte_i == 70u) return 116u;
    if (byte_i == 71u) return 190u;
    if (byte_i == 72u) return 69u;
    if (byte_i == 73u) return 133u;
    if (byte_i == 74u) return 201u;
    if (byte_i == 75u) return 116u;
    if (byte_i == 76u) return 7u;
    if (byte_i == 77u) return 68u;
    if (byte_i == 78u) return 137u;
    if (byte_i == 79u) return 208u;
    if (byte_i == 80u) return 137u;
    if (byte_i == 81u) return 68u;
    if (byte_i == 82u) return 36u;
    if (byte_i == 83u) return 80u;
    return 0u;
}

uint host_open_path_source_size(uint path_payload, uint source_kind, uint save_stack)
{
    if (source_kind == X86_AGG_SOURCE_LOCAL)
        return local_mem_r32_adjusted_size(X86_REG_EDI, path_payload, save_stack);
    if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint payload_base = param_aggregate_payload_base(path_payload);
        uint payload_ordinal = param_aggregate_payload_ordinal(path_payload);
        return ptr_slot_mem_r32_size(X86_REG_EDI, payload_base, payload_ordinal);
    }
    return mov_r32_imm32_size(X86_REG_EDI);
}

uint host_open_path_source_byte(uint path_payload, uint source_kind, uint save_stack, uint byte_i)
{
    if (source_kind == X86_AGG_SOURCE_LOCAL)
        return load_local_r32_adjusted_byte(X86_REG_EDI, path_payload, save_stack, byte_i);
    if (source_kind == X86_AGG_SOURCE_PARAM)
        return load_ptr_slot_r32_byte(
            X86_REG_EDI,
            param_aggregate_payload_base(path_payload),
            param_aggregate_payload_ordinal(path_payload),
            byte_i);
    // The GPU relocation pass materializes the final rodata address.
    return mov_r32_imm32_byte(X86_REG_EDI, 0u, byte_i);
}

uint host_open_path_macro_byte(uint dst, uint path_payload, uint source_kind, uint flags, uint mode, uint byte_i)
{
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;
    uint save_stack = print_save_stack_size();

    uint path_setup_size = host_open_path_source_size(path_payload, source_kind, save_stack);
    if (byte_i < path_setup_size)
        return host_open_path_source_byte(path_payload, source_kind, save_stack, byte_i);
    byte_i -= path_setup_size;

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_ESI, flags, byte_i);
    byte_i -= 5u;

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_EDX, mode, byte_i);
    byte_i -= 5u;

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_EAX, 2u, byte_i);
    byte_i -= 5u;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(64u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    uint dst_move = dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX);
    if (byte_i < dst_move)
        return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
    return 0u;
}

uint lea_r64_rsp_size(uint dst, uint disp)
{
    return valid_reg(dst) ? (disp <= 127u ? 5u : 8u) : 0u;
}

uint add_r32_imm8_size(uint reg)
{
    return valid_reg(reg) ? 3u + (needs_rex_modrm(0u, reg) ? 1u : 0u) : 0u;
}

uint host_path_open_finish_size(uint dst)
{
    return 7u +
           7u +
           print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_path_open_finish_byte(uint dst, uint byte_i)
{
    if (byte_i < 7u)
        return store_eax_rsp_disp32_byte(HOST_PATH_RESULT_DISP, byte_i);
    byte_i -= 7u;

    if (byte_i < 7u)
        return add_r64_rsp_imm32_byte(HOST_PATH_BUFFER_BYTES, byte_i);
    byte_i -= 7u;

    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    uint dst_move = dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX);
    if (byte_i < dst_move)
        return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
    return 0u;
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

uint host_path_buffer_copy_byte(uint byte_i)
{
    uint lea_size = lea_r64_rsp_size(X86_REG_EDI, 0u);
    if (byte_i < lea_size)
        return lea_r64_rsp_byte(X86_REG_EDI, 0u, byte_i);
    byte_i -= lea_size;

    uint zero_size = xor_r32_self_size(X86_REG_ECX);
    if (byte_i < zero_size)
        return xor_r32_r32_byte(X86_REG_ECX, byte_i);
    byte_i -= zero_size;

    uint cmp_size = cmp_r32_r32_size(X86_REG_ECX, X86_REG_R9D);
    if (byte_i < cmp_size)
        return cmp_r32_r32_byte(X86_REG_ECX, X86_REG_R9D, byte_i);
    byte_i -= cmp_size;

    uint step_size = add_r32_imm8_size(X86_REG_ECX);
    uint body_size = 4u + 3u + step_size + 2u;
    if (byte_i < 2u)
        return jcc_rel8_byte(0x74u, body_size, byte_i);
    byte_i -= 2u;

    if (byte_i < 4u)
        return mov_dl_m8_r8_rcx_byte(byte_i);
    byte_i -= 4u;

    if (byte_i < 3u)
        return mov_m8_rdi_rcx_dl_byte(byte_i);
    byte_i -= 3u;

    if (byte_i < step_size)
        return add_r32_imm8_byte(X86_REG_ECX, 1u, byte_i);
    byte_i -= step_size;

    if (byte_i < 2u)
    {
        uint back_distance = cmp_size + 2u + body_size;
        return jcc_rel8_byte(0xebu, 256u - back_distance, byte_i);
    }
    byte_i -= 2u;

    return mov_m8_rdi_r9_imm8_byte(0u, byte_i);
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

uint host_open_path_buffer_macro_byte(uint packed, uint dst, uint flags, uint mode, uint byte_i)
{
    uint path_ptr = packed_reg_a(packed);
    uint path_len = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return sub_r64_rsp_imm8_byte(16u, byte_i);
    byte_i -= 4u;

    uint load_ptr = host_arg_source_r32_size(X86_REG_R8D, path_ptr);
    if (byte_i < load_ptr)
        return host_arg_source_r32_byte(X86_REG_R8D, path_ptr, byte_i);
    byte_i -= load_ptr;

    uint load_len = host_arg_source_r32_size(X86_REG_R9D, path_len);
    if (byte_i < load_len)
        return host_arg_source_r32_byte(X86_REG_R9D, path_len, byte_i);
    byte_i -= load_len;

    if (byte_i < 7u)
        return sub_r64_rsp_imm32_byte(HOST_PATH_BUFFER_BYTES - 16u, byte_i);
    byte_i -= 7u;

    uint len_check = cmp_r32_imm_size(X86_REG_R9D, HOST_PATH_MAX_BYTES);
    if (byte_i < len_check)
        return cmp_r32_imm_byte(X86_REG_R9D, HOST_PATH_MAX_BYTES, byte_i);
    byte_i -= len_check;

    uint copy_size = host_path_buffer_copy_size();
    uint finish_size = host_path_open_finish_size(dst);
    uint normal_size = copy_size +
                       mov_r32_imm32_size(X86_REG_ESI) +
                       mov_r32_imm32_size(X86_REG_EDX) +
                       mov_r32_imm32_size(X86_REG_EAX) +
                       2u +
                       finish_size;
    uint fail_size = mov_r32_imm32_size(X86_REG_EAX) + finish_size;

    if (byte_i < 2u)
        return jcc_rel8_byte(0x77u, normal_size + 2u, byte_i);
    byte_i -= 2u;

    if (byte_i < copy_size)
        return host_path_buffer_copy_byte(byte_i);
    byte_i -= copy_size;

    uint flags_size = mov_r32_imm32_size(X86_REG_ESI);
    if (byte_i < flags_size)
        return mov_r32_imm32_byte(X86_REG_ESI, flags, byte_i);
    byte_i -= flags_size;

    uint mode_size = mov_r32_imm32_size(X86_REG_EDX);
    if (byte_i < mode_size)
        return mov_r32_imm32_byte(X86_REG_EDX, mode, byte_i);
    byte_i -= mode_size;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 2u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < finish_size)
        return host_path_open_finish_byte(dst, byte_i);
    byte_i -= finish_size;

    if (byte_i < 2u)
        return jcc_rel8_byte(0xebu, fail_size, byte_i);
    byte_i -= 2u;

    uint fail_value_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < fail_value_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 0xffffffffu, byte_i);
    byte_i -= fail_value_size;

    return host_path_open_finish_byte(dst, byte_i);
}

uint host_path_syscall_macro_byte(uint packed, uint dst, uint syscall_number, bool has_mode, uint byte_i)
{
    uint path_ptr = packed_reg_a(packed);
    uint path_len = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size) return print_save_regs_byte(byte_i);
    byte_i -= save_size;
    if (byte_i < 4u) return sub_r64_rsp_imm8_byte(16u, byte_i);
    byte_i -= 4u;
    uint load_ptr = host_arg_source_r32_size(X86_REG_R8D, path_ptr);
    if (byte_i < load_ptr) return host_arg_source_r32_byte(X86_REG_R8D, path_ptr, byte_i);
    byte_i -= load_ptr;
    uint load_len = host_arg_source_r32_size(X86_REG_R9D, path_len);
    if (byte_i < load_len) return host_arg_source_r32_byte(X86_REG_R9D, path_len, byte_i);
    byte_i -= load_len;
    if (byte_i < 7u) return sub_r64_rsp_imm32_byte(HOST_PATH_BUFFER_BYTES - 16u, byte_i);
    byte_i -= 7u;
    uint len_check = cmp_r32_imm_size(X86_REG_R9D, HOST_PATH_MAX_BYTES);
    if (byte_i < len_check) return cmp_r32_imm_byte(X86_REG_R9D, HOST_PATH_MAX_BYTES, byte_i);
    byte_i -= len_check;
    uint copy_size = host_path_buffer_copy_size();
    uint finish_size = host_path_open_finish_size(dst);
    uint normal_size = copy_size + (has_mode ? mov_r32_imm32_size(X86_REG_ESI) : 0u) +
                       mov_r32_imm32_size(X86_REG_EAX) + 2u + finish_size;
    uint fail_size = mov_r32_imm32_size(X86_REG_EAX) + finish_size;
    if (byte_i < 2u) return jcc_rel8_byte(0x77u, normal_size + 2u, byte_i);
    byte_i -= 2u;
    if (byte_i < copy_size) return host_path_buffer_copy_byte(byte_i);
    byte_i -= copy_size;
    if (has_mode)
    {
        uint mode_size = mov_r32_imm32_size(X86_REG_ESI);
        if (byte_i < mode_size) return mov_r32_imm32_byte(X86_REG_ESI, 493u, byte_i);
        byte_i -= mode_size;
    }
    uint syscall_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_size) return mov_r32_imm32_byte(X86_REG_EAX, syscall_number, byte_i);
    byte_i -= syscall_size;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;
    if (byte_i < finish_size) return host_path_open_finish_byte(dst, byte_i);
    byte_i -= finish_size;
    if (byte_i < 2u) return jcc_rel8_byte(0xebu, fail_size, byte_i);
    byte_i -= 2u;
    uint fail_value_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < fail_value_size) return mov_r32_imm32_byte(X86_REG_EAX, 0xffffffffu, byte_i);
    byte_i -= fail_value_size;
    return host_path_open_finish_byte(dst, byte_i);
}

uint host_second_path_buffer_copy_size()
{
    return lea_r64_rsp_size(X86_REG_ESI, HOST_PATH_BUFFER_BYTES) +
           xor_r32_self_size(X86_REG_ECX) +
           cmp_r32_r32_size(X86_REG_ECX, X86_REG_R11D) +
           2u + 4u + 3u + add_r32_imm8_size(X86_REG_ECX) + 2u + 5u;
}

uint host_second_path_buffer_copy_byte(uint byte_i)
{
    uint lea_size = lea_r64_rsp_size(X86_REG_ESI, HOST_PATH_BUFFER_BYTES);
    if (byte_i < lea_size) return lea_r64_rsp_byte(X86_REG_ESI, HOST_PATH_BUFFER_BYTES, byte_i);
    byte_i -= lea_size;
    uint zero_size = xor_r32_self_size(X86_REG_ECX);
    if (byte_i < zero_size) return xor_r32_r32_byte(X86_REG_ECX, byte_i);
    byte_i -= zero_size;
    uint cmp_size = cmp_r32_r32_size(X86_REG_ECX, X86_REG_R11D);
    if (byte_i < cmp_size) return cmp_r32_r32_byte(X86_REG_ECX, X86_REG_R11D, byte_i);
    byte_i -= cmp_size;
    uint step_size = add_r32_imm8_size(X86_REG_ECX);
    uint body_size = 4u + 3u + step_size + 2u;
    if (byte_i < 2u) return jcc_rel8_byte(0x74u, body_size, byte_i);
    byte_i -= 2u;
    if (byte_i < 4u)
    {
        if (byte_i == 0u) return 0x41u;
        if (byte_i == 1u) return 0x8au;
        if (byte_i == 2u) return 0x14u;
        return 0x0au;
    }
    byte_i -= 4u;
    if (byte_i < 3u)
    {
        if (byte_i == 0u) return 0x88u;
        if (byte_i == 1u) return 0x14u;
        return 0x0eu;
    }
    byte_i -= 3u;
    if (byte_i < step_size) return add_r32_imm8_byte(X86_REG_ECX, 1u, byte_i);
    byte_i -= step_size;
    if (byte_i < 2u)
    {
        uint back_distance = cmp_size + 2u + body_size;
        return jcc_rel8_byte(0xebu, 256u - back_distance, byte_i);
    }
    byte_i -= 2u;
    if (byte_i == 0u) return 0x42u;
    if (byte_i == 1u) return 0xc6u;
    if (byte_i == 2u) return 0x04u;
    if (byte_i == 3u) return 0x1eu;
    return 0u;
}

uint host_rename_finish_size(uint dst)
{
    return 14u + print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_rename_finish_byte(uint dst, uint byte_i)
{
    if (byte_i < 7u) return store_eax_rsp_disp32_byte(HOST_RENAME_RESULT_DISP, byte_i);
    byte_i -= 7u;
    if (byte_i < 7u) return add_r64_rsp_imm32_byte(HOST_RENAME_BUFFER_BYTES, byte_i);
    byte_i -= 7u;
    uint save_size = print_save_restore_size();
    if (byte_i < save_size) return print_restore_regs_byte(byte_i);
    byte_i -= save_size;
    return dst == X86_REG_EAX ? 0u : mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_rename_path_buffer_macro_byte(uint from_packed, uint to_packed, uint dst, uint byte_i)
{
    uint4 regs = uint4(packed_reg_a(from_packed), packed_reg_b(from_packed),
                       packed_reg_a(to_packed), packed_reg_b(to_packed));
    uint save_size = print_save_restore_size();
    if (byte_i < save_size) return print_save_regs_byte(byte_i);
    byte_i -= save_size;
    if (byte_i < 4u) return sub_r64_rsp_imm8_byte(16u, byte_i);
    byte_i -= 4u;
    uint4 dst_regs = uint4(X86_REG_R8D, X86_REG_R9D, X86_REG_R10D, X86_REG_R11D);
    for (uint i = 0u; i < 4u; i += 1u)
    {
        uint load_size = host_arg_source_r32_size(dst_regs[i], regs[i]);
        if (byte_i < load_size) return host_arg_source_r32_byte(dst_regs[i], regs[i], byte_i);
        byte_i -= load_size;
    }
    if (byte_i < 7u) return sub_r64_rsp_imm32_byte(HOST_RENAME_BUFFER_BYTES - 16u, byte_i);
    byte_i -= 7u;
    uint from_check = cmp_r32_imm_size(X86_REG_R9D, HOST_PATH_MAX_BYTES);
    if (byte_i < from_check) return cmp_r32_imm_byte(X86_REG_R9D, HOST_PATH_MAX_BYTES, byte_i);
    byte_i -= from_check;
    uint to_check = cmp_r32_imm_size(X86_REG_R11D, HOST_PATH_MAX_BYTES);
    uint copy_size = host_path_buffer_copy_size();
    uint second_copy_size = host_second_path_buffer_copy_size();
    uint finish_size = host_rename_finish_size(dst);
    uint normal_size = copy_size + second_copy_size + mov_r32_imm32_size(X86_REG_EAX) + 2u + finish_size;
    uint fail_size = mov_r32_imm32_size(X86_REG_EAX) + finish_size;
    if (byte_i < 2u) return jcc_rel8_byte(0x77u, to_check + 2u + normal_size + 2u, byte_i);
    byte_i -= 2u;
    if (byte_i < to_check) return cmp_r32_imm_byte(X86_REG_R11D, HOST_PATH_MAX_BYTES, byte_i);
    byte_i -= to_check;
    if (byte_i < 2u) return jcc_rel8_byte(0x77u, normal_size + 2u, byte_i);
    byte_i -= 2u;
    if (byte_i < copy_size) return host_path_buffer_copy_byte(byte_i);
    byte_i -= copy_size;
    if (byte_i < second_copy_size) return host_second_path_buffer_copy_byte(byte_i);
    byte_i -= second_copy_size;
    uint syscall_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_size) return mov_r32_imm32_byte(X86_REG_EAX, 82u, byte_i);
    byte_i -= syscall_size;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;
    if (byte_i < finish_size) return host_rename_finish_byte(dst, byte_i);
    byte_i -= finish_size;
    if (byte_i < 2u) return jcc_rel8_byte(0xebu, fail_size, byte_i);
    byte_i -= 2u;
    uint fail_value_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < fail_value_size) return mov_r32_imm32_byte(X86_REG_EAX, 0xffffffffu, byte_i);
    byte_i -= fail_value_size;
    return host_rename_finish_byte(dst, byte_i);
}

uint host_result_i32_finish_size(uint dst)
{
    return 8u + print_save_restore_size() +
           (dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX));
}

uint host_result_i32_finish_byte(uint dst, uint byte_i)
{
    if (byte_i < 4u) return store_eax_rsp_disp8_byte(80u, byte_i);
    byte_i -= 4u;
    if (byte_i < 4u) return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;
    uint restore = print_save_restore_size();
    if (byte_i < restore) return print_restore_regs_byte(byte_i);
    byte_i -= restore;
    return dst == X86_REG_EAX ? 0u : mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_clock_read_macro_byte(uint packed, uint dst, uint clock_id, uint byte_i)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    uint save = print_save_restore_size();
    if (byte_i < save) return print_save_regs_byte(byte_i);
    byte_i -= save;
    if (byte_i < 4u) return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;
    uint load_ptr = host_arg_source_r32_size(X86_REG_ESI, ptr);
    if (byte_i < load_ptr) return host_arg_source_r32_byte(X86_REG_ESI, ptr, byte_i);
    byte_i -= load_ptr;
    uint load_len = host_arg_source_r32_size(X86_REG_R9D, len);
    if (byte_i < load_len) return host_arg_source_r32_byte(X86_REG_R9D, len, byte_i);
    byte_i -= load_len;
    uint len_check = cmp_r32_imm_size(X86_REG_R9D, 16u);
    if (byte_i < len_check) return cmp_r32_imm_byte(X86_REG_R9D, 16u, byte_i);
    byte_i -= len_check;
    uint finish = host_result_i32_finish_size(dst);
    uint normal = mov_r32_imm32_size(X86_REG_EDI) + mov_r32_imm32_size(X86_REG_EAX) + 2u + finish;
    uint fail = mov_r32_imm32_size(X86_REG_EAX) + finish;
    if (byte_i < 2u) return jcc_rel8_byte(0x72u, normal + 2u, byte_i);
    byte_i -= 2u;
    uint clock_size = mov_r32_imm32_size(X86_REG_EDI);
    if (byte_i < clock_size) return mov_r32_imm32_byte(X86_REG_EDI, clock_id, byte_i);
    byte_i -= clock_size;
    uint syscall_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_size) return mov_r32_imm32_byte(X86_REG_EAX, 228u, byte_i);
    byte_i -= syscall_size;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;
    if (byte_i < finish) return host_result_i32_finish_byte(dst, byte_i);
    byte_i -= finish;
    if (byte_i < 2u) return jcc_rel8_byte(0xebu, fail, byte_i);
    byte_i -= 2u;
    uint fail_value = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < fail_value) return mov_r32_imm32_byte(X86_REG_EAX, 0xffffffffu, byte_i);
    byte_i -= fail_value;
    return host_result_i32_finish_byte(dst, byte_i);
}

uint host_sleep_ms_i32_macro_byte(uint milliseconds, uint dst, uint byte_i)
{
    uint save = print_save_restore_size();
    if (byte_i < save) return print_save_regs_byte(byte_i);
    byte_i -= save;
    if (byte_i < 4u) return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;
    uint load_ms = host_arg_source_r32_size(X86_REG_R10D, milliseconds);
    if (byte_i < load_ms) return host_arg_source_r32_byte(X86_REG_R10D, milliseconds, byte_i);
    byte_i -= load_ms;
    uint check = cmp_r32_imm_size(X86_REG_R10D, 0u);
    if (byte_i < check) return cmp_r32_imm_byte(X86_REG_R10D, 0u, byte_i);
    byte_i -= check;
    uint finish = host_result_i32_finish_size(dst);
    uint normal = mov_r32_r32_size(X86_REG_EDX, X86_REG_R10D) +
                  xor_r32_self_size(X86_REG_EDI) + xor_r32_self_size(X86_REG_ESI) +
                  mov_r32_imm32_size(X86_REG_EAX) + 2u + finish;
    uint fail = mov_r32_imm32_size(X86_REG_EAX) + finish;
    if (byte_i < 2u) return jcc_rel8_byte(0x7cu, normal + 2u, byte_i);
    byte_i -= 2u;
    uint timeout_move = mov_r32_r32_size(X86_REG_EDX, X86_REG_R10D);
    if (byte_i < timeout_move) return mov_r32_r32_byte(X86_REG_EDX, X86_REG_R10D, byte_i);
    byte_i -= timeout_move;
    uint zero_edi = xor_r32_self_size(X86_REG_EDI);
    if (byte_i < zero_edi) return xor_r32_r32_byte(X86_REG_EDI, byte_i);
    byte_i -= zero_edi;
    uint zero_esi = xor_r32_self_size(X86_REG_ESI);
    if (byte_i < zero_esi) return xor_r32_r32_byte(X86_REG_ESI, byte_i);
    byte_i -= zero_esi;
    uint syscall_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_size) return mov_r32_imm32_byte(X86_REG_EAX, 7u, byte_i);
    byte_i -= syscall_size;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;
    if (byte_i < finish) return host_result_i32_finish_byte(dst, byte_i);
    byte_i -= finish;
    if (byte_i < 2u) return jcc_rel8_byte(0xebu, fail, byte_i);
    byte_i -= 2u;
    uint fail_value = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < fail_value) return mov_r32_imm32_byte(X86_REG_EAX, 0xffffffffu, byte_i);
    byte_i -= fail_value;
    return host_result_i32_finish_byte(dst, byte_i);
}

uint host_realloc_macro_byte(uint old_packed, uint new_packed, uint dst, uint byte_i)
{
    uint3 src = uint3(packed_reg_a(old_packed), packed_reg_b(old_packed), packed_reg_a(new_packed));
    uint3 target = uint3(X86_REG_EDI, X86_REG_ESI, X86_REG_EDX);
    uint save = print_save_restore_size();
    if (byte_i < save) return print_save_regs_byte(byte_i);
    byte_i -= save;
    if (byte_i < 4u) return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;
    for (uint i = 0u; i < 3u; i += 1u)
    {
        uint load = host_arg_source_r32_size(target[i], src[i]);
        if (byte_i < load) return host_arg_source_r32_byte(target[i], src[i], byte_i);
        byte_i -= load;
    }
    uint flags = mov_r32_imm32_size(X86_REG_R10D);
    if (byte_i < flags) return mov_r32_imm32_byte(X86_REG_R10D, 1u, byte_i);
    byte_i -= flags;
    uint syscall_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_size) return mov_r32_imm32_byte(X86_REG_EAX, 25u, byte_i);
    byte_i -= syscall_size;
    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;
    if (byte_i < 2u) return test_r32_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= 2u;
    uint zero_size = xor_r32_self_size(X86_REG_EAX);
    if (byte_i < 2u) return jcc_rel8_byte(0x79u, zero_size, byte_i);
    byte_i -= 2u;
    if (byte_i < zero_size) return xor_r32_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= zero_size;
    return host_result_i32_finish_byte(dst, byte_i);
}

uint host_read_i32_macro_byte(uint packed, uint dst, uint byte_i)
{
    uint handle = packed_reg_a(packed);
    uint fallback = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint fd_move = handle == X86_REG_R8D ? 0u : mov_r32_r32_size(X86_REG_R8D, handle);
    if (byte_i < fd_move)
        return mov_r32_r32_byte(X86_REG_R8D, handle, byte_i);
    byte_i -= fd_move;

    uint fallback_move = fallback == X86_REG_EAX ? 0u : mov_r32_r32_size(X86_REG_EAX, fallback);
    if (byte_i < fallback_move)
        return mov_r32_r32_byte(X86_REG_EAX, fallback, byte_i);
    byte_i -= fallback_move;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(64u, byte_i);
    byte_i -= 4u;

    if (byte_i < 84u)
        return read_i32_core_byte(byte_i);
    byte_i -= 84u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    uint dst_move = dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX);
    if (byte_i < dst_move)
        return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
    return 0u;
}

uint host_fs_close_macro_byte(uint packed, uint byte_i)
{
    uint handle = packed_reg_a(packed);
    uint dst = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint handle_load = host_arg_source_r32_size(X86_REG_EDI, handle);
    if (byte_i < handle_load)
        return host_arg_source_r32_byte(X86_REG_EDI, handle, byte_i);
    byte_i -= handle_load;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 3u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(80u, byte_i);
    byte_i -= 4u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    uint dst_move = dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX);
    if (byte_i < dst_move)
        return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
    return 0u;
}

uint host_fs_read_write_macro_byte(uint packed, uint len, uint dst, uint syscall_number, uint byte_i)
{
    uint handle = packed_reg_a(packed);
    uint ptr = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint handle_load = host_arg_source_r32_size(X86_REG_EDI, handle);
    if (byte_i < handle_load)
        return host_arg_source_r32_byte(X86_REG_EDI, handle, byte_i);
    byte_i -= handle_load;

    uint ptr_load = host_arg_source_r32_size(X86_REG_ESI, ptr);
    if (byte_i < ptr_load)
        return host_arg_source_r32_byte(X86_REG_ESI, ptr, byte_i);
    byte_i -= ptr_load;

    uint len_load = host_arg_source_r32_size(X86_REG_EDX, len);
    if (byte_i < len_load)
        return host_arg_source_r32_byte(X86_REG_EDX, len, byte_i);
    byte_i -= len_load;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, syscall_number, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(80u, byte_i);
    byte_i -= 4u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    uint dst_move = dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX);
    if (byte_i < dst_move)
        return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
    return 0u;
}

uint host_stdio_read_write_macro_byte(uint packed, uint dst, uint fd, uint syscall_number, uint byte_i)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint fd_size = mov_r32_imm32_size(X86_REG_EDI);
    if (byte_i < fd_size)
        return mov_r32_imm32_byte(X86_REG_EDI, fd, byte_i);
    byte_i -= fd_size;

    uint ptr_load = host_arg_source_r32_size(X86_REG_ESI, ptr);
    if (byte_i < ptr_load)
        return host_arg_source_r32_byte(X86_REG_ESI, ptr, byte_i);
    byte_i -= ptr_load;

    uint len_load = host_arg_source_r32_size(X86_REG_EDX, len);
    if (byte_i < len_load)
        return host_arg_source_r32_byte(X86_REG_EDX, len, byte_i);
    byte_i -= len_load;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, syscall_number, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(80u, byte_i);
    byte_i -= 4u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    uint dst_move = dst == X86_REG_EAX ? 0u : mov_r32_r32_size(dst, X86_REG_EAX);
    if (byte_i < dst_move)
        return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
    return 0u;
}

uint host_secure_u32_macro_byte(uint dst, uint byte_i)
{
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint zero_size = xor_r32_self_size(X86_REG_EAX);
    if (byte_i < zero_size)
        return xor_r32_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= zero_size;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(12u, byte_i);
    byte_i -= 4u;

    if (byte_i < 5u)
        return lea_r64_rsp_byte(X86_REG_EDI, 12u, byte_i);
    byte_i -= 5u;

    uint len_size = mov_r32_imm32_size(X86_REG_ESI);
    if (byte_i < len_size)
        return mov_r32_imm32_byte(X86_REG_ESI, 4u, byte_i);
    byte_i -= len_size;

    uint flags_size = xor_r32_self_size(X86_REG_EDX);
    if (byte_i < flags_size)
        return xor_r32_r32_byte(X86_REG_EDX, byte_i);
    byte_i -= flags_size;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 318u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    uint load_size = 4u + (needs_rex_modrm(X86_REG_EAX, 4u) ? 1u : 0u);
    if (byte_i < load_size)
        return load_rsp_disp8_r32_byte(X86_REG_EAX, 12u, byte_i);
    byte_i -= load_size;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(80u, byte_i);
    byte_i -= 4u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_fill_secure_bytes_macro_byte(uint packed, uint dst, uint byte_i)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint ptr_load = host_arg_source_r32_size(X86_REG_EDI, ptr);
    if (byte_i < ptr_load)
        return host_arg_source_r32_byte(X86_REG_EDI, ptr, byte_i);
    byte_i -= ptr_load;

    uint len_load = host_arg_source_r32_size(X86_REG_ESI, len);
    if (byte_i < len_load)
        return host_arg_source_r32_byte(X86_REG_ESI, len, byte_i);
    byte_i -= len_load;

    uint flags_size = xor_r32_self_size(X86_REG_EDX);
    if (byte_i < flags_size)
        return xor_r32_r32_byte(X86_REG_EDX, byte_i);
    byte_i -= flags_size;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 318u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(80u, byte_i);
    byte_i -= 4u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_alloc_macro_byte(uint packed, uint dst, uint byte_i)
{
    uint size = packed_reg_a(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    uint size_move = size == X86_REG_ESI ? 0u : mov_r32_r32_size(X86_REG_ESI, size);
    if (byte_i < size_move)
        return mov_r32_r32_byte(X86_REG_ESI, size, byte_i);
    byte_i -= size_move;

    uint addr_zero = xor_r32_self_size(X86_REG_EDI);
    if (byte_i < addr_zero)
        return xor_r32_r32_byte(X86_REG_EDI, byte_i);
    byte_i -= addr_zero;

    uint prot_size = mov_r32_imm32_size(X86_REG_EDX);
    if (byte_i < prot_size)
        return mov_r32_imm32_byte(X86_REG_EDX, 3u, byte_i);
    byte_i -= prot_size;

    uint flags_size = mov_r32_imm32_size(X86_REG_R10D);
    if (byte_i < flags_size)
        return mov_r32_imm32_byte(X86_REG_R10D, 98u, byte_i);
    byte_i -= flags_size;

    uint fd_size = mov_r32_imm32_size(X86_REG_R8D);
    if (byte_i < fd_size)
        return mov_r32_imm32_byte(X86_REG_R8D, 0xffffffffu, byte_i);
    byte_i -= fd_size;

    uint offset_zero = xor_r32_self_size(X86_REG_R9D);
    if (byte_i < offset_zero)
        return xor_r32_r32_byte(X86_REG_R9D, byte_i);
    byte_i -= offset_zero;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 9u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 2u)
        return test_r32_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= 2u;

    if (byte_i < 2u)
        return jcc_rel8_byte(0x79u, 2u, byte_i);
    byte_i -= 2u;

    uint fallback_zero = xor_r32_self_size(X86_REG_EAX);
    if (byte_i < fallback_zero)
        return xor_r32_r32_byte(X86_REG_EAX, byte_i);
    byte_i -= fallback_zero;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(64u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_dealloc_macro_byte(uint packed, uint byte_i)
{
    uint ptr = packed_reg_a(packed);
    uint size = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    uint ptr_move = ptr == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, ptr);
    if (byte_i < ptr_move)
        return mov_r32_r32_byte(X86_REG_EDI, ptr, byte_i);
    byte_i -= ptr_move;

    uint size_move = size == X86_REG_ESI ? 0u : mov_r32_r32_size(X86_REG_ESI, size);
    if (byte_i < size_move)
        return mov_r32_r32_byte(X86_REG_ESI, size, byte_i);
    byte_i -= size_move;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 11u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    return 0u;
}

uint load_process_stack_r32_byte(uint dst, uint byte_i)
{
    bool rex = needs_rex_modrm(dst, X86_REG_R15D);
    uint cursor = 0u;
    if (rex)
    {
        if (byte_i == cursor) return rex_modrm(dst, X86_REG_R15D);
        cursor += 1u;
    }
    if (byte_i == cursor) return 0x8bu;
    if (byte_i == cursor + 1u) return ((dst & 7u) << 3u) | 7u;
    return 0u;
}

uint host_unix_seconds_macro_byte(uint dst, uint byte_i)
{
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    uint zero_arg_size = xor_r32_self_size(X86_REG_EDI);
    if (byte_i < zero_arg_size)
        return xor_r32_r32_byte(X86_REG_EDI, byte_i);
    byte_i -= zero_arg_size;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 201u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return store_eax_rsp_disp8_byte(64u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint arg_len_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 131u;
    if (byte_i == 1u) return 255u;
    if (byte_i == 2u) return 0u;
    if (byte_i == 3u) return 124u;
    if (byte_i == 4u) return 31u;
    if (byte_i == 5u) return 65u;
    if (byte_i == 6u) return 139u;
    if (byte_i == 7u) return 7u;
    if (byte_i == 8u) return 57u;
    if (byte_i == 9u) return 199u;
    if (byte_i == 10u) return 125u;
    if (byte_i == 11u) return 24u;
    if (byte_i == 12u) return 73u;
    if (byte_i == 13u) return 141u;
    if (byte_i == 14u) return 119u;
    if (byte_i == 15u) return 8u;
    if (byte_i == 16u) return 72u;
    if (byte_i == 17u) return 99u;
    if (byte_i == 18u) return 255u;
    if (byte_i == 19u) return 72u;
    if (byte_i == 20u) return 139u;
    if (byte_i == 21u) return 52u;
    if (byte_i == 22u) return 254u;
    if (byte_i == 23u) return 49u;
    if (byte_i == 24u) return 192u;
    if (byte_i == 25u) return 128u;
    if (byte_i == 26u) return 60u;
    if (byte_i == 27u) return 6u;
    if (byte_i == 28u) return 0u;
    if (byte_i == 29u) return 116u;
    if (byte_i == 30u) return 10u;
    if (byte_i == 31u) return 131u;
    if (byte_i == 32u) return 192u;
    if (byte_i == 33u) return 1u;
    if (byte_i == 34u) return 235u;
    if (byte_i == 35u) return 245u;
    if (byte_i == 36u) return 184u;
    if (byte_i == 37u) return 255u;
    if (byte_i == 38u) return 255u;
    if (byte_i == 39u) return 255u;
    if (byte_i == 40u) return 255u;
    if (byte_i == 41u) return 137u;
    if (byte_i == 42u) return 68u;
    if (byte_i == 43u) return 36u;
    if (byte_i == 44u) return 80u;
    return 0u;
}

uint arg_read_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 131u;
    if (byte_i == 1u) return 255u;
    if (byte_i == 2u) return 0u;
    if (byte_i == 3u) return 124u;
    if (byte_i == 4u) return 45u;
    if (byte_i == 5u) return 65u;
    if (byte_i == 6u) return 139u;
    if (byte_i == 7u) return 7u;
    if (byte_i == 8u) return 57u;
    if (byte_i == 9u) return 199u;
    if (byte_i == 10u) return 125u;
    if (byte_i == 11u) return 38u;
    if (byte_i == 12u) return 77u;
    if (byte_i == 13u) return 141u;
    if (byte_i == 14u) return 71u;
    if (byte_i == 15u) return 8u;
    if (byte_i == 16u) return 72u;
    if (byte_i == 17u) return 99u;
    if (byte_i == 18u) return 255u;
    if (byte_i == 19u) return 77u;
    if (byte_i == 20u) return 139u;
    if (byte_i == 21u) return 4u;
    if (byte_i == 22u) return 248u;
    if (byte_i == 23u) return 49u;
    if (byte_i == 24u) return 192u;
    if (byte_i == 25u) return 133u;
    if (byte_i == 26u) return 210u;
    if (byte_i == 27u) return 116u;
    if (byte_i == 28u) return 26u;
    if (byte_i == 29u) return 57u;
    if (byte_i == 30u) return 208u;
    if (byte_i == 31u) return 125u;
    if (byte_i == 32u) return 22u;
    if (byte_i == 33u) return 65u;
    if (byte_i == 34u) return 138u;
    if (byte_i == 35u) return 12u;
    if (byte_i == 36u) return 0u;
    if (byte_i == 37u) return 128u;
    if (byte_i == 38u) return 249u;
    if (byte_i == 39u) return 0u;
    if (byte_i == 40u) return 116u;
    if (byte_i == 41u) return 13u;
    if (byte_i == 42u) return 136u;
    if (byte_i == 43u) return 12u;
    if (byte_i == 44u) return 6u;
    if (byte_i == 45u) return 131u;
    if (byte_i == 46u) return 192u;
    if (byte_i == 47u) return 1u;
    if (byte_i == 48u) return 235u;
    if (byte_i == 49u) return 235u;
    if (byte_i == 50u) return 184u;
    if (byte_i == 51u) return 255u;
    if (byte_i == 52u) return 255u;
    if (byte_i == 53u) return 255u;
    if (byte_i == 54u) return 255u;
    if (byte_i == 55u) return 137u;
    if (byte_i == 56u) return 68u;
    if (byte_i == 57u) return 36u;
    if (byte_i == 58u) return 80u;
    return 0u;
}

uint host_arg_len_macro_byte(uint index, uint dst, uint byte_i)
{
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint index_load = host_arg_source_r32_size(X86_REG_EDI, index);
    if (byte_i < index_load)
        return host_arg_source_r32_byte(X86_REG_EDI, index, byte_i);
    byte_i -= index_load;

    if (byte_i < 45u)
        return arg_len_core_byte(byte_i);
    byte_i -= 45u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_arg_read_macro_byte(uint packed, uint len, uint dst, uint byte_i)
{
    uint index = packed_reg_a(packed);
    uint ptr = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint index_load = host_arg_source_r32_size(X86_REG_EDI, index);
    if (byte_i < index_load)
        return host_arg_source_r32_byte(X86_REG_EDI, index, byte_i);
    byte_i -= index_load;

    uint ptr_load = host_arg_source_r32_size(X86_REG_ESI, ptr);
    if (byte_i < ptr_load)
        return host_arg_source_r32_byte(X86_REG_ESI, ptr, byte_i);
    byte_i -= ptr_load;

    uint len_load = host_arg_source_r32_size(X86_REG_EDX, len);
    if (byte_i < len_load)
        return host_arg_source_r32_byte(X86_REG_EDX, len, byte_i);
    byte_i -= len_load;

    if (byte_i < 59u)
        return arg_read_core_byte(byte_i);
    byte_i -= 59u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint current_dir_read_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 72u;
    if (byte_i == 1u) return 133u;
    if (byte_i == 2u) return 192u;
    if (byte_i == 3u) return 120u;
    if (byte_i == 4u) return 17u;
    if (byte_i == 5u) return 49u;
    if (byte_i == 6u) return 192u;
    if (byte_i == 7u) return 57u;
    if (byte_i == 8u) return 240u;
    if (byte_i == 9u) return 115u;
    if (byte_i == 10u) return 16u;
    if (byte_i == 11u) return 128u;
    if (byte_i == 12u) return 60u;
    if (byte_i == 13u) return 7u;
    if (byte_i == 14u) return 0u;
    if (byte_i == 15u) return 116u;
    if (byte_i == 16u) return 10u;
    if (byte_i == 17u) return 131u;
    if (byte_i == 18u) return 192u;
    if (byte_i == 19u) return 1u;
    if (byte_i == 20u) return 235u;
    if (byte_i == 21u) return 241u;
    if (byte_i == 22u) return 184u;
    if (byte_i == 23u) return 255u;
    if (byte_i == 24u) return 255u;
    if (byte_i == 25u) return 255u;
    if (byte_i == 26u) return 255u;
    if (byte_i == 27u) return 137u;
    if (byte_i == 28u) return 68u;
    if (byte_i == 29u) return 36u;
    if (byte_i == 30u) return 80u;
    return 0u;
}

uint host_current_dir_read_macro_byte(uint packed, uint dst, uint byte_i)
{
    uint ptr = packed_reg_a(packed);
    uint len = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint ptr_load = host_arg_source_r32_size(X86_REG_EDI, ptr);
    if (byte_i < ptr_load)
        return host_arg_source_r32_byte(X86_REG_EDI, ptr, byte_i);
    byte_i -= ptr_load;

    uint len_load = host_arg_source_r32_size(X86_REG_ESI, len);
    if (byte_i < len_load)
        return host_arg_source_r32_byte(X86_REG_ESI, len, byte_i);
    byte_i -= len_load;

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 79u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 31u)
        return current_dir_read_core_byte(byte_i);
    byte_i -= 31u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint env_count_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 65u;
    if (byte_i == 1u) return 139u;
    if (byte_i == 2u) return 7u;
    if (byte_i == 3u) return 73u;
    if (byte_i == 4u) return 141u;
    if (byte_i == 5u) return 127u;
    if (byte_i == 6u) return 8u;
    if (byte_i == 7u) return 72u;
    if (byte_i == 8u) return 99u;
    if (byte_i == 9u) return 192u;
    if (byte_i == 10u) return 72u;
    if (byte_i == 11u) return 141u;
    if (byte_i == 12u) return 124u;
    if (byte_i == 13u) return 199u;
    if (byte_i == 14u) return 8u;
    if (byte_i == 15u) return 49u;
    if (byte_i == 16u) return 192u;
    if (byte_i == 17u) return 72u;
    if (byte_i == 18u) return 131u;
    if (byte_i == 19u) return 60u;
    if (byte_i == 20u) return 199u;
    if (byte_i == 21u) return 0u;
    if (byte_i == 22u) return 116u;
    if (byte_i == 23u) return 5u;
    if (byte_i == 24u) return 131u;
    if (byte_i == 25u) return 192u;
    if (byte_i == 26u) return 1u;
    if (byte_i == 27u) return 235u;
    if (byte_i == 28u) return 244u;
    if (byte_i == 29u) return 137u;
    if (byte_i == 30u) return 68u;
    if (byte_i == 31u) return 36u;
    if (byte_i == 32u) return 80u;
    return 0u;
}

uint env_key_len_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 133u;
    if (byte_i == 1u) return 255u;
    if (byte_i == 2u) return 120u;
    if (byte_i == 3u) return 47u;
    if (byte_i == 4u) return 65u;
    if (byte_i == 5u) return 139u;
    if (byte_i == 6u) return 7u;
    if (byte_i == 7u) return 73u;
    if (byte_i == 8u) return 141u;
    if (byte_i == 9u) return 119u;
    if (byte_i == 10u) return 8u;
    if (byte_i == 11u) return 72u;
    if (byte_i == 12u) return 99u;
    if (byte_i == 13u) return 192u;
    if (byte_i == 14u) return 72u;
    if (byte_i == 15u) return 141u;
    if (byte_i == 16u) return 116u;
    if (byte_i == 17u) return 198u;
    if (byte_i == 18u) return 8u;
    if (byte_i == 19u) return 72u;
    if (byte_i == 20u) return 99u;
    if (byte_i == 21u) return 255u;
    if (byte_i == 22u) return 72u;
    if (byte_i == 23u) return 139u;
    if (byte_i == 24u) return 52u;
    if (byte_i == 25u) return 254u;
    if (byte_i == 26u) return 72u;
    if (byte_i == 27u) return 133u;
    if (byte_i == 28u) return 246u;
    if (byte_i == 29u) return 116u;
    if (byte_i == 30u) return 20u;
    if (byte_i == 31u) return 49u;
    if (byte_i == 32u) return 192u;
    if (byte_i == 33u) return 138u;
    if (byte_i == 34u) return 12u;
    if (byte_i == 35u) return 6u;
    if (byte_i == 36u) return 128u;
    if (byte_i == 37u) return 249u;
    if (byte_i == 38u) return 0u;
    if (byte_i == 39u) return 116u;
    if (byte_i == 40u) return 15u;
    if (byte_i == 41u) return 128u;
    if (byte_i == 42u) return 249u;
    if (byte_i == 43u) return 61u;
    if (byte_i == 44u) return 116u;
    if (byte_i == 45u) return 10u;
    if (byte_i == 46u) return 131u;
    if (byte_i == 47u) return 192u;
    if (byte_i == 48u) return 1u;
    if (byte_i == 49u) return 235u;
    if (byte_i == 50u) return 238u;
    if (byte_i == 51u) return 184u;
    if (byte_i == 52u) return 255u;
    if (byte_i == 53u) return 255u;
    if (byte_i == 54u) return 255u;
    if (byte_i == 55u) return 255u;
    if (byte_i == 56u) return 137u;
    if (byte_i == 57u) return 68u;
    if (byte_i == 58u) return 36u;
    if (byte_i == 59u) return 80u;
    return 0u;
}

uint env_key_read_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 133u;
    if (byte_i == 1u) return 255u;
    if (byte_i == 2u) return 120u;
    if (byte_i == 3u) return 59u;
    if (byte_i == 4u) return 65u;
    if (byte_i == 5u) return 139u;
    if (byte_i == 6u) return 7u;
    if (byte_i == 7u) return 77u;
    if (byte_i == 8u) return 141u;
    if (byte_i == 9u) return 71u;
    if (byte_i == 10u) return 8u;
    if (byte_i == 11u) return 72u;
    if (byte_i == 12u) return 99u;
    if (byte_i == 13u) return 192u;
    if (byte_i == 14u) return 77u;
    if (byte_i == 15u) return 141u;
    if (byte_i == 16u) return 68u;
    if (byte_i == 17u) return 192u;
    if (byte_i == 18u) return 8u;
    if (byte_i == 19u) return 72u;
    if (byte_i == 20u) return 99u;
    if (byte_i == 21u) return 255u;
    if (byte_i == 22u) return 77u;
    if (byte_i == 23u) return 139u;
    if (byte_i == 24u) return 4u;
    if (byte_i == 25u) return 248u;
    if (byte_i == 26u) return 77u;
    if (byte_i == 27u) return 133u;
    if (byte_i == 28u) return 192u;
    if (byte_i == 29u) return 116u;
    if (byte_i == 30u) return 32u;
    if (byte_i == 31u) return 49u;
    if (byte_i == 32u) return 192u;
    if (byte_i == 33u) return 133u;
    if (byte_i == 34u) return 210u;
    if (byte_i == 35u) return 116u;
    if (byte_i == 36u) return 31u;
    if (byte_i == 37u) return 57u;
    if (byte_i == 38u) return 208u;
    if (byte_i == 39u) return 115u;
    if (byte_i == 40u) return 27u;
    if (byte_i == 41u) return 65u;
    if (byte_i == 42u) return 138u;
    if (byte_i == 43u) return 12u;
    if (byte_i == 44u) return 0u;
    if (byte_i == 45u) return 128u;
    if (byte_i == 46u) return 249u;
    if (byte_i == 47u) return 0u;
    if (byte_i == 48u) return 116u;
    if (byte_i == 49u) return 18u;
    if (byte_i == 50u) return 128u;
    if (byte_i == 51u) return 249u;
    if (byte_i == 52u) return 61u;
    if (byte_i == 53u) return 116u;
    if (byte_i == 54u) return 13u;
    if (byte_i == 55u) return 136u;
    if (byte_i == 56u) return 12u;
    if (byte_i == 57u) return 6u;
    if (byte_i == 58u) return 131u;
    if (byte_i == 59u) return 192u;
    if (byte_i == 60u) return 1u;
    if (byte_i == 61u) return 235u;
    if (byte_i == 62u) return 230u;
    if (byte_i == 63u) return 184u;
    if (byte_i == 64u) return 255u;
    if (byte_i == 65u) return 255u;
    if (byte_i == 66u) return 255u;
    if (byte_i == 67u) return 255u;
    if (byte_i == 68u) return 137u;
    if (byte_i == 69u) return 68u;
    if (byte_i == 70u) return 36u;
    if (byte_i == 71u) return 80u;
    return 0u;
}

uint host_var_count_macro_byte(uint dst, uint byte_i)
{
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < 33u)
        return env_count_core_byte(byte_i);
    byte_i -= 33u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_var_key_len_macro_byte(uint index, uint dst, uint byte_i)
{
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint index_load = host_arg_source_r32_size(X86_REG_EDI, index);
    if (byte_i < index_load)
        return host_arg_source_r32_byte(X86_REG_EDI, index, byte_i);
    byte_i -= index_load;

    if (byte_i < 60u)
        return env_key_len_core_byte(byte_i);
    byte_i -= 60u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_var_key_read_macro_byte(uint packed, uint len, uint dst, uint byte_i)
{
    uint index = packed_reg_a(packed);
    uint ptr = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint index_load = host_arg_source_r32_size(X86_REG_EDI, index);
    if (byte_i < index_load)
        return host_arg_source_r32_byte(X86_REG_EDI, index, byte_i);
    byte_i -= index_load;

    uint ptr_load = host_arg_source_r32_size(X86_REG_ESI, ptr);
    if (byte_i < ptr_load)
        return host_arg_source_r32_byte(X86_REG_ESI, ptr, byte_i);
    byte_i -= ptr_load;

    uint len_load = host_arg_source_r32_size(X86_REG_EDX, len);
    if (byte_i < len_load)
        return host_arg_source_r32_byte(X86_REG_EDX, len, byte_i);
    byte_i -= len_load;

    if (byte_i < 72u)
        return env_key_read_core_byte(byte_i);
    byte_i -= 72u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint env_var_len_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 65u;
    if (byte_i == 1u) return 139u;
    if (byte_i == 2u) return 7u;
    if (byte_i == 3u) return 77u;
    if (byte_i == 4u) return 141u;
    if (byte_i == 5u) return 71u;
    if (byte_i == 6u) return 8u;
    if (byte_i == 7u) return 72u;
    if (byte_i == 8u) return 99u;
    if (byte_i == 9u) return 192u;
    if (byte_i == 10u) return 77u;
    if (byte_i == 11u) return 141u;
    if (byte_i == 12u) return 68u;
    if (byte_i == 13u) return 192u;
    if (byte_i == 14u) return 8u;
    if (byte_i == 15u) return 77u;
    if (byte_i == 16u) return 139u;
    if (byte_i == 17u) return 8u;
    if (byte_i == 18u) return 77u;
    if (byte_i == 19u) return 133u;
    if (byte_i == 20u) return 201u;
    if (byte_i == 21u) return 116u;
    if (byte_i == 22u) return 52u;
    if (byte_i == 23u) return 49u;
    if (byte_i == 24u) return 210u;
    if (byte_i == 25u) return 57u;
    if (byte_i == 26u) return 242u;
    if (byte_i == 27u) return 115u;
    if (byte_i == 28u) return 14u;
    if (byte_i == 29u) return 138u;
    if (byte_i == 30u) return 12u;
    if (byte_i == 31u) return 23u;
    if (byte_i == 32u) return 65u;
    if (byte_i == 33u) return 56u;
    if (byte_i == 34u) return 12u;
    if (byte_i == 35u) return 17u;
    if (byte_i == 36u) return 117u;
    if (byte_i == 37u) return 31u;
    if (byte_i == 38u) return 131u;
    if (byte_i == 39u) return 194u;
    if (byte_i == 40u) return 1u;
    if (byte_i == 41u) return 235u;
    if (byte_i == 42u) return 238u;
    if (byte_i == 43u) return 65u;
    if (byte_i == 44u) return 128u;
    if (byte_i == 45u) return 60u;
    if (byte_i == 46u) return 17u;
    if (byte_i == 47u) return 61u;
    if (byte_i == 48u) return 117u;
    if (byte_i == 49u) return 19u;
    if (byte_i == 50u) return 77u;
    if (byte_i == 51u) return 141u;
    if (byte_i == 52u) return 76u;
    if (byte_i == 53u) return 17u;
    if (byte_i == 54u) return 1u;
    if (byte_i == 55u) return 49u;
    if (byte_i == 56u) return 192u;
    if (byte_i == 57u) return 65u;
    if (byte_i == 58u) return 128u;
    if (byte_i == 59u) return 60u;
    if (byte_i == 60u) return 1u;
    if (byte_i == 61u) return 0u;
    if (byte_i == 62u) return 116u;
    if (byte_i == 63u) return 16u;
    if (byte_i == 64u) return 131u;
    if (byte_i == 65u) return 192u;
    if (byte_i == 66u) return 1u;
    if (byte_i == 67u) return 235u;
    if (byte_i == 68u) return 244u;
    if (byte_i == 69u) return 73u;
    if (byte_i == 70u) return 131u;
    if (byte_i == 71u) return 192u;
    if (byte_i == 72u) return 8u;
    if (byte_i == 73u) return 235u;
    if (byte_i == 74u) return 196u;
    if (byte_i == 75u) return 184u;
    if (byte_i == 76u) return 255u;
    if (byte_i == 77u) return 255u;
    if (byte_i == 78u) return 255u;
    if (byte_i == 79u) return 255u;
    if (byte_i == 80u) return 137u;
    if (byte_i == 81u) return 68u;
    if (byte_i == 82u) return 36u;
    if (byte_i == 83u) return 80u;
    return 0u;
}

uint env_var_read_core_byte(uint byte_i)
{
    if (byte_i == 0u) return 65u;
    if (byte_i == 1u) return 137u;
    if (byte_i == 2u) return 210u;
    if (byte_i == 3u) return 65u;
    if (byte_i == 4u) return 137u;
    if (byte_i == 5u) return 203u;
    if (byte_i == 6u) return 65u;
    if (byte_i == 7u) return 139u;
    if (byte_i == 8u) return 7u;
    if (byte_i == 9u) return 77u;
    if (byte_i == 10u) return 141u;
    if (byte_i == 11u) return 71u;
    if (byte_i == 12u) return 8u;
    if (byte_i == 13u) return 72u;
    if (byte_i == 14u) return 99u;
    if (byte_i == 15u) return 192u;
    if (byte_i == 16u) return 77u;
    if (byte_i == 17u) return 141u;
    if (byte_i == 18u) return 68u;
    if (byte_i == 19u) return 192u;
    if (byte_i == 20u) return 8u;
    if (byte_i == 21u) return 77u;
    if (byte_i == 22u) return 139u;
    if (byte_i == 23u) return 8u;
    if (byte_i == 24u) return 77u;
    if (byte_i == 25u) return 133u;
    if (byte_i == 26u) return 201u;
    if (byte_i == 27u) return 116u;
    if (byte_i == 28u) return 68u;
    if (byte_i == 29u) return 49u;
    if (byte_i == 30u) return 210u;
    if (byte_i == 31u) return 57u;
    if (byte_i == 32u) return 242u;
    if (byte_i == 33u) return 115u;
    if (byte_i == 34u) return 14u;
    if (byte_i == 35u) return 138u;
    if (byte_i == 36u) return 12u;
    if (byte_i == 37u) return 23u;
    if (byte_i == 38u) return 65u;
    if (byte_i == 39u) return 56u;
    if (byte_i == 40u) return 12u;
    if (byte_i == 41u) return 17u;
    if (byte_i == 42u) return 117u;
    if (byte_i == 43u) return 47u;
    if (byte_i == 44u) return 131u;
    if (byte_i == 45u) return 194u;
    if (byte_i == 46u) return 1u;
    if (byte_i == 47u) return 235u;
    if (byte_i == 48u) return 238u;
    if (byte_i == 49u) return 65u;
    if (byte_i == 50u) return 128u;
    if (byte_i == 51u) return 60u;
    if (byte_i == 52u) return 17u;
    if (byte_i == 53u) return 61u;
    if (byte_i == 54u) return 117u;
    if (byte_i == 55u) return 35u;
    if (byte_i == 56u) return 77u;
    if (byte_i == 57u) return 141u;
    if (byte_i == 58u) return 76u;
    if (byte_i == 59u) return 17u;
    if (byte_i == 60u) return 1u;
    if (byte_i == 61u) return 49u;
    if (byte_i == 62u) return 192u;
    if (byte_i == 63u) return 69u;
    if (byte_i == 64u) return 133u;
    if (byte_i == 65u) return 219u;
    if (byte_i == 66u) return 116u;
    if (byte_i == 67u) return 34u;
    if (byte_i == 68u) return 68u;
    if (byte_i == 69u) return 57u;
    if (byte_i == 70u) return 216u;
    if (byte_i == 71u) return 115u;
    if (byte_i == 72u) return 29u;
    if (byte_i == 73u) return 65u;
    if (byte_i == 74u) return 138u;
    if (byte_i == 75u) return 12u;
    if (byte_i == 76u) return 1u;
    if (byte_i == 77u) return 128u;
    if (byte_i == 78u) return 249u;
    if (byte_i == 79u) return 0u;
    if (byte_i == 80u) return 116u;
    if (byte_i == 81u) return 20u;
    if (byte_i == 82u) return 65u;
    if (byte_i == 83u) return 136u;
    if (byte_i == 84u) return 12u;
    if (byte_i == 85u) return 2u;
    if (byte_i == 86u) return 131u;
    if (byte_i == 87u) return 192u;
    if (byte_i == 88u) return 1u;
    if (byte_i == 89u) return 235u;
    if (byte_i == 90u) return 233u;
    if (byte_i == 91u) return 73u;
    if (byte_i == 92u) return 131u;
    if (byte_i == 93u) return 192u;
    if (byte_i == 94u) return 8u;
    if (byte_i == 95u) return 235u;
    if (byte_i == 96u) return 180u;
    if (byte_i == 97u) return 184u;
    if (byte_i == 98u) return 255u;
    if (byte_i == 99u) return 255u;
    if (byte_i == 100u) return 255u;
    if (byte_i == 101u) return 255u;
    if (byte_i == 102u) return 137u;
    if (byte_i == 103u) return 68u;
    if (byte_i == 104u) return 36u;
    if (byte_i == 105u) return 80u;
    return 0u;
}

uint host_var_len_macro_byte(uint packed, uint dst, uint byte_i)
{
    uint key_ptr = packed_reg_a(packed);
    uint key_len = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint key_ptr_load = host_arg_source_r32_size(X86_REG_EDI, key_ptr);
    if (byte_i < key_ptr_load)
        return host_arg_source_r32_byte(X86_REG_EDI, key_ptr, byte_i);
    byte_i -= key_ptr_load;

    uint key_len_load = host_arg_source_r32_size(X86_REG_ESI, key_len);
    if (byte_i < key_len_load)
        return host_arg_source_r32_byte(X86_REG_ESI, key_len, byte_i);
    byte_i -= key_len_load;

    if (byte_i < 84u)
        return env_var_len_core_byte(byte_i);
    byte_i -= 84u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_var_read_macro_byte(uint key_pair, uint value_pair, uint dst, uint byte_i)
{
    uint key_ptr = packed_reg_a(key_pair);
    uint key_len = packed_reg_b(key_pair);
    uint value_ptr = packed_reg_a(value_pair);
    uint value_len = packed_reg_b(value_pair);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint key_ptr_load = host_arg_source_r32_size(X86_REG_EDI, key_ptr);
    if (byte_i < key_ptr_load)
        return host_arg_source_r32_byte(X86_REG_EDI, key_ptr, byte_i);
    byte_i -= key_ptr_load;

    uint key_len_load = host_arg_source_r32_size(X86_REG_ESI, key_len);
    if (byte_i < key_len_load)
        return host_arg_source_r32_byte(X86_REG_ESI, key_len, byte_i);
    byte_i -= key_len_load;

    uint value_ptr_load = host_arg_source_r32_size(X86_REG_EDX, value_ptr);
    if (byte_i < value_ptr_load)
        return host_arg_source_r32_byte(X86_REG_EDX, value_ptr, byte_i);
    byte_i -= value_ptr_load;

    uint value_len_load = host_arg_source_r32_size(X86_REG_ECX, value_len);
    if (byte_i < value_len_load)
        return host_arg_source_r32_byte(X86_REG_ECX, value_len, byte_i);
    byte_i -= value_len_load;

    if (byte_i < 106u)
        return env_var_read_core_byte(byte_i);
    byte_i -= 106u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    if (dst == X86_REG_EAX)
        return 0u;
    return mov_r32_r32_byte(dst, X86_REG_EAX, byte_i);
}

uint host_write_byte_macro_byte(uint packed, uint value, uint dst, bool immediate_newline, uint byte_i)
{
    uint handle = packed_reg_a(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint handle_move = handle == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, handle);
    if (byte_i < handle_move)
        return mov_r32_r32_byte(X86_REG_EDI, handle, byte_i);
    byte_i -= handle_move;

    uint value_move = immediate_newline ? 0u : mov_r32_r32_size(X86_REG_EDX, value);
    if (byte_i < value_move)
        return mov_r32_r32_byte(X86_REG_EDX, value, byte_i);
    byte_i -= value_move;

    if (byte_i < 5u)
        return lea_rsi_rsp_disp8_byte(15u, byte_i);
    byte_i -= 5u;

    if (immediate_newline)
    {
        if (byte_i < 3u)
            return mov_m8_rsi_imm8_byte(10u, byte_i);
        byte_i -= 3u;
    }
    else
    {
        if (byte_i < 2u)
            return mov_m8_rsi_dl_byte(byte_i);
        byte_i -= 2u;
    }

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_EDX, 1u, byte_i);
    byte_i -= 5u;

    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_EAX, 1u, byte_i);
    byte_i -= 5u;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(0u, 16u, byte_i);
    byte_i -= 4u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    return xor_r32_r32_byte(dst, byte_i);
}

uint print_i32_fd_macro_byte(uint packed, uint dst, uint byte_i)
{
    uint handle = packed_reg_a(packed);
    uint src = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;

    if (byte_i < 4u)
        return alu_r64_rsp_imm8_byte(1u, 16u, byte_i);
    byte_i -= 4u;

    uint fd_save = handle == X86_REG_R9D ? 0u : mov_r32_r32_size(X86_REG_R9D, handle);
    if (byte_i < fd_save)
        return mov_r32_r32_byte(X86_REG_R9D, handle, byte_i);
    byte_i -= fd_save;

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
    if (byte_i < 5u)
        return mov_r32_imm32_byte(X86_REG_ECX, 0u, byte_i);
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

    uint fd_use = mov_r32_r32_size(X86_REG_EDI, X86_REG_R9D);
    if (byte_i < fd_use)
        return mov_r32_r32_byte(X86_REG_EDI, X86_REG_R9D, byte_i);
    byte_i -= fd_use;

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
    byte_i -= save_size;
    return xor_r32_r32_byte(dst, byte_i);
}

uint host_text_write_macro_byte(uint packed, uint text_payload, uint text_len, uint byte_i)
{
    uint handle = packed_reg_a(packed);
    uint dst = packed_reg_b(packed);
    uint save_size = print_save_restore_size();
    if (byte_i < save_size)
        return print_save_regs_byte(byte_i);
    byte_i -= save_size;
    uint save_stack = print_save_stack_size();

    uint handle_move_size = handle == X86_REG_EDI ? 0u : mov_r32_r32_size(X86_REG_EDI, handle);
    if (byte_i < handle_move_size)
        return mov_r32_r32_byte(X86_REG_EDI, handle, byte_i);
    byte_i -= handle_move_size;

    if (text_len == INVALID)
    {
        uint ptr_load_size = local_mem_r32_adjusted_size(X86_REG_ESI, text_payload, save_stack);
        if (byte_i < ptr_load_size)
            return load_local_r32_adjusted_byte(X86_REG_ESI, text_payload, save_stack, byte_i);
        byte_i -= ptr_load_size;

        uint len_load_size = local_mem_r32_adjusted_size(X86_REG_EDX, text_payload + 1u, save_stack);
        if (byte_i < len_load_size)
            return load_local_r32_adjusted_byte(X86_REG_EDX, text_payload + 1u, save_stack, byte_i);
        byte_i -= len_load_size;
    }
    else
    {
        uint ptr_move_size = mov_r32_imm32_size(X86_REG_ESI);
        if (byte_i < ptr_move_size)
            // The GPU relocation pass materializes the final rodata address.
            return mov_r32_imm32_byte(X86_REG_ESI, 0u, byte_i);
        byte_i -= ptr_move_size;

        uint len_move_size = mov_r32_imm32_size(X86_REG_EDX);
        if (byte_i < len_move_size)
            return mov_r32_imm32_byte(
                X86_REG_EDX,
                rodata_payload_len_for_node(text_payload, text_len),
                byte_i);
        byte_i -= len_move_size;
    }

    uint syscall_number_size = mov_r32_imm32_size(X86_REG_EAX);
    if (byte_i < syscall_number_size)
        return mov_r32_imm32_byte(X86_REG_EAX, 1u, byte_i);
    byte_i -= syscall_number_size;

    if (byte_i == 0u) return 0x0fu;
    if (byte_i == 1u) return 0x05u;
    byte_i -= 2u;

    if (byte_i < save_size)
        return print_restore_regs_byte(byte_i);
    byte_i -= save_size;

    return xor_r32_r32_byte(dst, byte_i);
}

uint host_alloc_failed_macro_byte(uint byte_i)
{
    // exit_group is unnecessary for these single-threaded artifacts. The
    // ordinary exit syscall is non-returning and preserves the language ABI's
    // allocation-failure contract through nested calls.
    if (byte_i == 0u) return 0xbfu;
    if (byte_i == 1u) return 1u;
    if (byte_i >= 2u && byte_i < 5u) return 0u;
    if (byte_i == 5u) return 0xb8u;
    if (byte_i == 6u) return 60u;
    if (byte_i >= 7u && byte_i < 10u) return 0u;
    if (byte_i == 10u) return 0x0fu;
    if (byte_i == 11u) return 0x05u;
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

uint instruction_byte(uint inst_i, uint byte_i)
{
    uint kind = inst_kind_tag(inst_i);
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
        if (byte_i == 0u) return 0xbeu;
        if (byte_i < 5u) return 0u;
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
        return mov_r32_imm_compact_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
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
    if (kind == X86_INST_V_HOST_PROCESS_EXIT)
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
    if (kind == X86_INST_V_RETURN_FUNC_R32)
        return return_func_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_PRINT_I32)
        return print_i32_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_TEXT_WRITE)
        return host_text_write_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_OPEN_WRITE_PATH)
        return host_open_path_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], 577u, 420u, byte_i);
    if (kind == X86_INST_V_HOST_OPEN_READ_PATH)
        return host_open_path_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], 0u, 0u, byte_i);
    if (kind == X86_INST_V_HOST_WRITE_I32)
        return print_i32_fd_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_READ_I32)
        return host_read_i32_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_SECURE_U32)
        return host_secure_u32_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_ALLOC)
        return host_alloc_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_DEALLOC)
        return host_dealloc_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_ARGC)
        return load_process_stack_r32_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_UNIX_SECONDS)
        return host_unix_seconds_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_ARG_LEN)
        return host_arg_len_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_ARG_READ)
        return host_arg_read_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_CURRENT_DIR_READ)
        return host_current_dir_read_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_VAR_COUNT)
        return host_var_count_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_VAR_KEY_LEN)
        return host_var_key_len_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_VAR_KEY_READ)
        return host_var_key_read_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_VAR_LEN)
        return host_var_len_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_VAR_READ)
        return host_var_read_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_CLOSE_FILE)
        return host_fs_close_macro_byte(x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_FS_READ)
        return host_fs_read_write_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], 0u, byte_i);
    if (kind == X86_INST_V_HOST_FS_WRITE)
        return host_fs_read_write_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], 1u, byte_i);
    if (kind == X86_INST_V_HOST_FS_OPEN_READ)
        return host_open_path_buffer_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 0u, 0u, byte_i);
    if (kind == X86_INST_V_HOST_FS_OPEN_WRITE)
        return host_open_path_buffer_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 577u, 420u, byte_i);
    if (kind == X86_INST_V_HOST_FS_OPEN_APPEND)
        return host_open_path_buffer_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 1089u, 420u, byte_i);
    if (kind == X86_INST_V_HOST_STDIN_READ)
        return host_stdio_read_write_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 0u, 0u, byte_i);
    if (kind == X86_INST_V_HOST_STDOUT_WRITE)
        return host_stdio_read_write_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 1u, 1u, byte_i);
    if (kind == X86_INST_V_HOST_STDERR_WRITE)
        return host_stdio_read_write_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 2u, 1u, byte_i);
    if (kind == X86_INST_V_HOST_FILL_SECURE_BYTES)
        return host_fill_secure_bytes_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_FS_REMOVE_FILE)
        return host_path_syscall_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 87u, false, byte_i);
    if (kind == X86_INST_V_HOST_FS_CREATE_DIR)
        return host_path_syscall_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 83u, true, byte_i);
    if (kind == X86_INST_V_HOST_FS_REMOVE_DIR)
        return host_path_syscall_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 84u, false, byte_i);
    if (kind == X86_INST_V_HOST_FS_RENAME)
        return host_rename_path_buffer_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_TIME_MONOTONIC_READ)
        return host_clock_read_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 1u, byte_i);
    if (kind == X86_INST_V_HOST_TIME_SYSTEM_READ)
        return host_clock_read_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], 0u, byte_i);
    if (kind == X86_INST_V_HOST_TIME_SLEEP_MS_I32)
        return host_sleep_ms_i32_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_REALLOC)
        return host_realloc_macro_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_HOST_ALLOC_FAILED)
        return host_alloc_failed_macro_byte(byte_i);
    if (kind == X86_INST_V_HOST_WRITE_BYTE)
        return host_write_byte_macro_byte(x86_inst_arg0[inst_i], packed_reg_b(x86_inst_arg0[inst_i]), x86_inst_arg1[inst_i], false, byte_i);
    if (kind == X86_INST_V_HOST_WRITE_NEWLINE)
        return host_write_byte_macro_byte(x86_inst_arg0[inst_i], 0u, packed_reg_b(x86_inst_arg0[inst_i]), true, byte_i);
    if (kind == X86_INST_V_LOAD_LOCAL_R32)
        return load_local_r32_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_STORE_LOCAL_R32)
        return store_local_r32_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_LOAD_LOCAL_INDEX_R32)
        return checked_load_local_index_r32_byte(
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_STORE_LOCAL_INDEX_R32)
        return checked_store_local_index_r32_byte(
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_LOAD_PARAM_INDEX_R32)
        return checked_load_param_index_r32_byte(
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_STORE_PARAM_INDEX_R32)
        return checked_store_param_index_r32_byte(
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_STORE_LOCAL_IMM32)
        return x86_inst_arg1[inst_i] == 0u
                   ? store_local_zero_byte(x86_inst_arg0[inst_i], byte_i)
                   : store_local_imm32_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_STORE_LOCAL_RODATA_PTR)
        return store_local_imm32_byte(
            x86_inst_arg0[inst_i],
            0u,
            byte_i);
    if (kind == X86_INST_V_STORE_RET_PTR_R32)
        return store_ptr_slot_r32_byte(X86_REG_EDI, x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_COPY_AGG_RET)
        return copy_agg_ret_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_STORE_RET_PTR_IMM32)
        return x86_inst_arg0[inst_i] == 0u
                   ? store_ptr_slot_zero_byte(X86_REG_EDI, x86_inst_arg1[inst_i], byte_i)
                   : store_ptr_slot_imm32_byte(X86_REG_EDI, x86_inst_arg1[inst_i], x86_inst_arg0[inst_i], byte_i);
    if (kind == X86_INST_V_LOAD_PTR_SLOT_R32)
        return load_ptr_slot_r32_byte(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], x86_inst_arg2[inst_i], byte_i);
    if (kind == X86_INST_V_MATCH_TAG_BRANCH)
        return match_tag_branch_byte(
            inst_i,
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_FOR_ARRAY_BRANCH)
        return for_array_branch_byte(
            inst_i,
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_FOR_ARRAY_LOAD)
        return for_array_load_byte(
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_FOR_PARAM_ARRAY_LOAD)
        return for_param_array_load_byte(
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_FOR_ARRAY_INC_JMP)
        return for_array_inc_jmp_byte(
            inst_i,
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_FOR_INTERVAL_BRANCH)
        return for_interval_branch_byte(
            inst_i,
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            byte_i);
    if (kind == X86_INST_V_COPY_LOCAL_R32)
        return copy_local_r32_byte(
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            byte_i);
    if (kind == X86_INST_V_CALL_MIXED_DIRECT)
        return call_mixed_macro_byte(
            inst_i,
            x86_inst_arg0[inst_i],
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            inst_call_save_mask(inst_i),
            byte_i);
    if (kind == X86_INST_V_CALL_MIXED_EXTERNAL)
        return call_mixed_macro_byte(
            inst_i,
            0u,
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            inst_call_save_mask(inst_i),
            byte_i);
    if (kind == X86_INST_V_ENTRY_STACK_JMP)
        return entry_stack_jmp_byte(inst_i, x86_inst_arg0[inst_i], x86_inst_arg1[inst_i], byte_i);
    if (kind == X86_INST_V_EXIT_ZERO)
        return exit_zero_macro_byte(byte_i);
    return 0u;
}

void scatter_text_byte(uint text_pos, uint byte_value)
{
    uint word_i = ELF_TEXT_WORD_OFFSET + (text_pos >> 2u);
    uint lane_shift = (text_pos & 3u) * 8u;
    atomic_u32_or(out_words, word_i, (byte_value & 0xffu) << lane_shift);
}

void scatter_instruction_bytes(uint inst_i)
{
    uint offset = x86_inst_byte_offset[inst_i];
    uint size = x86_inst_size[inst_i];
    uint text_len = x86_text_len[0u];
    if (offset > text_len || size > text_len - offset)
        return;

    for (uint byte_i = 0u; byte_i < X86_MAX_ENCODED_INST_BYTES; byte_i += 1u)
    {
        if (byte_i < size)
            scatter_text_byte(offset + byte_i, instruction_byte(inst_i, byte_i));
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint inst_i = linear_dispatch_id(tid);
    bool text_ok = text_status[0u] == X86_TEXT_OK && text_status[1u] == 0u;
    bool reloc_ok = reloc_status[0u] == X86_RELOC_OK && reloc_status[1u] == 0u;
    bool upstream_ok = text_ok && reloc_ok;
    uint text_len = upstream_ok ? x86_text_len[0u] : 0u;
    bool file_len_ok = text_len <= 0xffffffffu - ELF_TEXT_OFFSET;
    uint file_len = file_len_ok ? ELF_TEXT_OFFSET + text_len : 0xffffffffu;
    bool capacity_ok = upstream_ok && file_len_ok && file_len <= gParams.out_capacity;
    bool ok = upstream_ok && capacity_ok;
    uint inst_count = upstream_ok ? text_status[3u] : 0u;

    if (inst_i == 0u)
    {
        uint reloc_error = reloc_status[1u] == 0u ? X86_ERR_RELOC : reloc_status[1u];
        encode_status[0u] = ok ? X86_ENCODE_OK : 0u;
        encode_status[1u] = ok ? 0u : (!text_ok ? text_status[1u] : (!reloc_ok ? reloc_error : X86_ERR_OUTPUT_TOO_SMALL));
        encode_status[2u] = ok ? 0xffffffffu : (!text_ok ? text_status[2u] : (!reloc_ok ? reloc_status[2u] : gParams.out_capacity));
        encode_status[3u] = ok ? text_len : 0u;
    }

    if (!ok || inst_i >= inst_count)
        return;

    scatter_instruction_bytes(inst_i);
}
