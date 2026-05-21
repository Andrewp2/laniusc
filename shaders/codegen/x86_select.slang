// Direct x86_64 instruction selection from allocated virtual instructions.
//
// The selected instruction records are derived from node-generated virtual
// instruction rows after GPU liveness and register allocation. This pass does
// not inspect source text, token spelling, helper names, or function-body
// shapes.

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

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_phys_reg;
StructuredBuffer<uint> x86_virtual_call_live_reg_mask;
StructuredBuffer<uint> x86_virtual_regalloc_status;
StructuredBuffer<uint> x86_func_first_virtual_row;
StructuredBuffer<uint> x86_func_first_virtual_row_status;
StructuredBuffer<uint> x86_decl_layout_status;
StructuredBuffer<uint> x86_func_meta;
StructuredBuffer<uint> x86_virtual_func_slot;

RWStructuredBuffer<uint> x86_inst_kind;
RWStructuredBuffer<uint> x86_inst_arg0;
RWStructuredBuffer<uint> x86_inst_arg1;
RWStructuredBuffer<uint> x86_inst_arg2;
RWStructuredBuffer<uint> select_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint X86_SELECT_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_REGALLOC_OK = 1u;
static const uint X86_FUNC_FIRST_VIRTUAL_ROW_OK = 1u;
static const uint X86_ERR_SELECT = 17u;

static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_INTRINSIC = 7u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_LOOP = 11u;
static const uint X86_VINST_TRANSFER = 12u;
static const uint X86_VINST_LOAD_LOCAL = 13u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_LOAD_LOCAL_INDEX = 15u;
static const uint X86_VINST_STORE_LOCAL_IMM = 16u;
static const uint X86_VINST_FOR_ARRAY_BRANCH = 17u;
static const uint X86_VINST_FOR_ARRAY_LOAD = 18u;
static const uint X86_VINST_FOR_ARRAY_INC_JMP = 19u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_VINST_LOAD_PARAM_INDEX = 21u;
static const uint X86_VINST_STORE_RET_PTR = 22u;
static const uint X86_VINST_COPY_AGG_RET = 23u;
static const uint X86_VINST_RETURN_VOID = 24u;
static const uint X86_VINST_STORE_RET_PTR_IMM = 25u;
static const uint X86_VINST_LOAD_PARAM_SLOT = 26u;
static const uint X86_VINST_MATCH_TAG_BRANCH = 27u;
static const uint X86_VINST_FOR_INTERVAL_BRANCH = 28u;
static const uint X86_VINST_COPY_LOCAL = 29u;
static const uint X86_ARG_SCALAR = 1u;
static const uint X86_ARG_LOCAL_PTR = 2u;
static const uint X86_ARG_PARAM_PTR = 3u;

static const uint X86_INST_RET = 16u;
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
static const uint X86_INTRINSIC_TEXT_WRITE = 1u;
static const uint X86_OP_ADD_I32 = 1u;
static const uint X86_OP_MUL_I32 = 3u;
static const uint X86_OP_AND_BOOL = 4u;
static const uint X86_OP_OR_BOOL = 5u;
static const uint X86_OP_BIT_AND_I32 = 8u;
static const uint X86_OP_BIT_OR_I32 = 9u;
static const uint X86_OP_BIT_XOR = 10u;

static const uint FUNC_META_MAIN_SLOT = 2u;
static const uint MIN_X86_STACK_FRAME_BYTES = 16u;

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
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

uint entry_frame_size()
{
    uint local_slots = x86_decl_layout_status[3u];
    uint bytes = max((local_slots + 3u) * 4u, MIN_X86_STACK_FRAME_BYTES);
    return (bytes + 15u) & 0xfffffff0u;
}

uint selected_inst_count()
{
    return virtual_inst_count() + 2u;
}

bool upstream_ok()
{
    uint inst_count = virtual_inst_count();
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u &&
           x86_virtual_inst_status[3u] <= gParams.inst_capacity &&
           selected_inst_count() <= gParams.inst_capacity &&
           x86_virtual_regalloc_status[0u] == X86_VIRTUAL_REGALLOC_OK &&
           x86_virtual_regalloc_status[1u] == 0u &&
           x86_virtual_regalloc_status[3u] == inst_count &&
           x86_func_first_virtual_row_status[0u] == X86_FUNC_FIRST_VIRTUAL_ROW_OK &&
           x86_func_first_virtual_row_status[1u] == 0u &&
           x86_func_first_virtual_row_status[3u] == inst_count;
}

void publish_error(uint detail, uint extra)
{
    publish_stage_error_min_detail_extra4(
        select_status,
        X86_ERR_SELECT,
        detail,
        extra);
}

bool has_value_def(uint row, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

bool phys_reg_for_value(uint row, uint inst_count, out uint reg)
{
    reg = INVALID;
    if (!has_value_def(row, inst_count))
        return false;
    reg = x86_virtual_phys_reg[row];
    return reg != INVALID;
}

bool target_valid(uint target, uint inst_count)
{
    return target != INVALID && target <= inst_count;
}

uint selected_target(uint virtual_target, uint inst_count)
{
    return virtual_target == inst_count ? inst_count + 1u : virtual_target + 1u;
}

bool main_entry_target(uint inst_count, out uint target)
{
    target = INVALID;
    uint main_slot = x86_func_meta[FUNC_META_MAIN_SLOT];
    if (main_slot >= gParams.n_tokens)
        return false;

    uint main_row = x86_func_first_virtual_row[main_slot];
    if (main_row == INVALID || main_row >= inst_count)
        return false;

    target = selected_target(main_row, inst_count);
    return true;
}

uint pack_regs(uint a, uint b)
{
    return pack_u8x4(a, b, 0u, 0u);
}

bool binary_op_commutative(uint op)
{
    return op == X86_OP_ADD_I32 ||
           op == X86_OP_MUL_I32 ||
           op == X86_OP_AND_BOOL ||
           op == X86_OP_OR_BOOL ||
           op == X86_OP_BIT_AND_I32 ||
           op == X86_OP_BIT_OR_I32 ||
           op == X86_OP_BIT_XOR;
}

uint mixed_arg_count(uint info)
{
    return packed_u8_at(info, 0u);
}

bool mixed_has_aggregate_return(uint info)
{
    return ((info >> 8u) & 1u) != 0u;
}

uint mixed_arg_kind(uint info, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u2_at_offset(info, 12u, ordinal);
    return 0u;
}

uint call_saved_reg_slot(uint reg)
{
    if (reg == X86_REG_ECX) return 0u;
    if (reg == X86_REG_EDX) return 1u;
    if (reg == X86_REG_ESI) return 2u;
    if (reg == X86_REG_EDI) return 3u;
    if (reg == X86_REG_R8D) return 4u;
    if (reg == X86_REG_R9D) return 5u;
    if (reg == X86_REG_R10D) return 6u;
    if (reg == X86_REG_R11D) return 7u;
    return INVALID;
}

uint call_saved_reg_mask_bit(uint reg)
{
    uint slot = call_saved_reg_slot(reg);
    return slot == INVALID ? 0u : (1u << slot);
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
    return INVALID;
}

uint call_arg_payload_at(uint ordinal, uint arg0, uint arg1, uint arg2, uint arg3)
{
    return ordinal == 0u
        ? arg0
        : (ordinal == 1u ? arg1 : (ordinal == 2u ? arg2 : arg3));
}

bool call_arg_move_writes_target(uint kind, uint payload, uint target)
{
    if (kind == X86_ARG_SCALAR || kind == X86_ARG_PARAM_PTR)
        return payload != target;
    return kind == X86_ARG_LOCAL_PTR;
}

uint call_arg_clobber_mask_before(
    uint info,
    uint ordinal,
    uint arg_count,
    uint arg0,
    uint arg1,
    uint arg2,
    uint arg3,
    bool aggregate_return)
{
    uint mask = aggregate_return ? call_saved_reg_mask_bit(X86_REG_EDI) : 0u;
    [unroll]
    for (uint prev = 0u; prev < 4u; prev += 1u)
    {
        if (prev >= ordinal || prev >= arg_count)
            continue;
        uint target = mixed_target_reg(prev, aggregate_return);
        uint payload = call_arg_payload_at(prev, arg0, arg1, arg2, arg3);
        if (call_arg_move_writes_target(mixed_arg_kind(info, prev), payload, target))
            mask |= call_saved_reg_mask_bit(target);
    }
    return mask;
}

uint call_arg_save_mask(
    uint info,
    uint arg_count,
    uint arg0,
    uint arg1,
    uint arg2,
    uint arg3,
    bool aggregate_return)
{
    uint mask = 0u;
    [unroll]
    for (uint ordinal = 0u; ordinal < 4u; ordinal += 1u)
    {
        if (ordinal >= arg_count || mixed_arg_kind(info, ordinal) != X86_ARG_SCALAR)
            continue;
        uint payload_bit = call_saved_reg_mask_bit(
            call_arg_payload_at(ordinal, arg0, arg1, arg2, arg3));
        uint clobbered_before = call_arg_clobber_mask_before(
            info,
            ordinal,
            arg_count,
            arg0,
            arg1,
            arg2,
            arg3,
            aggregate_return);
        if ((payload_bit & clobbered_before) != 0u)
            mask |= payload_bit;
    }
    return mask;
}

uint pack_kind_with_call_save_mask(uint kind, uint save_mask)
{
    return kind | ((save_mask & 0xffu) << 8u);
}

uint mixed_arg_payload(uint row, uint ordinal)
{
    uint4 args = x86_virtual_inst_args[row];
    uint payload_row = args.z;
    if (payload_row == INVALID || payload_row >= virtual_inst_count() || ordinal >= 4u)
        return INVALID;
    return x86_virtual_inst_args[payload_row][ordinal];
}

bool selected_mixed_arg_payload(uint row, uint info, uint ordinal, uint inst_count, out uint payload)
{
    payload = INVALID;
    uint kind = mixed_arg_kind(info, ordinal);
    uint raw = mixed_arg_payload(row, ordinal);
    if (kind == X86_ARG_SCALAR)
        return phys_reg_for_value(raw, inst_count, payload);
    if (kind == X86_ARG_LOCAL_PTR || kind == X86_ARG_PARAM_PTR)
    {
        payload = raw;
        return raw != INVALID;
    }
    return false;
}

bool select_virtual_inst(uint row, uint inst_count)
{
    uint4 inst = x86_virtual_inst_record[row];
    uint4 args = x86_virtual_inst_args[row];
    uint op = inst.z;
    uint out_row = row + 1u;

    if (inst.x == INVALID || op == 0u)
    {
        x86_inst_kind[out_row] = 0u;
        x86_inst_arg0[out_row] = 0u;
        x86_inst_arg1[out_row] = 0u;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_IMM_I32)
    {
        uint dst = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_MOV_R32_IMM32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.x;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_PARAM)
    {
        uint dst = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_PARAM_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.z;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_UNARY)
    {
        uint dst = INVALID;
        uint src = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_UNARY_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = dst;
        x86_inst_arg2[out_row] = src;
        return true;
    }

    if (op == X86_VINST_BINARY)
    {
        uint dst = INVALID;
        uint left = INVALID;
        uint right = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, left) ||
            !phys_reg_for_value(args.z, inst_count, right))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_BINARY_R32_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = dst;
        x86_inst_arg2[out_row] = binary_op_commutative(args.x) && dst == right && dst != left
                                      ? pack_regs(right, left)
                                      : pack_regs(left, right);
        return true;
    }

    if (op == X86_VINST_COMPARE)
    {
        uint dst = INVALID;
        uint left = INVALID;
        uint right = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, left) ||
            !phys_reg_for_value(args.z, inst_count, right))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_COMPARE_R32_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = dst;
        x86_inst_arg2[out_row] = pack_regs(left, right);
        return true;
    }

    if (op == X86_VINST_CALL_MIXED)
    {
        if (!target_valid(args.x, inst_count))
            return false;
        uint info = args.w;
        uint arg_count = mixed_arg_count(info);
        if (arg_count > 4u)
            return false;
        bool aggregate_return = mixed_has_aggregate_return(info);
        uint dest_payload = args.y;
        if (!aggregate_return && !phys_reg_for_value(row, inst_count, dest_payload))
            return false;

        uint arg0 = 0u;
        uint arg1 = 0u;
        uint arg2 = 0u;
        uint arg3 = 0u;
        if (arg_count >= 1u &&
            !selected_mixed_arg_payload(row, info, 0u, inst_count, arg0))
            return false;
        if (arg_count >= 2u &&
            !selected_mixed_arg_payload(row, info, 1u, inst_count, arg1))
            return false;
        if (arg_count >= 3u &&
            !selected_mixed_arg_payload(row, info, 2u, inst_count, arg2))
            return false;
        if (arg_count >= 4u &&
            !selected_mixed_arg_payload(row, info, 3u, inst_count, arg3))
            return false;

        uint save_mask = x86_virtual_call_live_reg_mask[row] |
                         call_arg_save_mask(info, arg_count, arg0, arg1, arg2, arg3, aggregate_return);
        x86_inst_kind[out_row] = pack_kind_with_call_save_mask(
            X86_INST_V_CALL_MIXED_DIRECT,
            save_mask);
        x86_inst_arg0[out_row] = selected_target(args.x, inst_count);
        x86_inst_arg1[out_row] = pack_u8x4(
                                     aggregate_return ? 1u : 0u,
                                     dest_payload,
                                     arg_count,
                                     0u) |
                                 pack_u2x4_at_offset(
                                     24u,
                                     mixed_arg_kind(info, 0u),
                                     mixed_arg_kind(info, 1u),
                                     mixed_arg_kind(info, 2u),
                                     mixed_arg_kind(info, 3u));
        x86_inst_arg2[out_row] = pack_u8x4(arg0, arg1, arg2, arg3);
        return true;
    }

    if (op == X86_VINST_INTRINSIC)
    {
        if (args.x != X86_INTRINSIC_TEXT_WRITE)
            return false;
        uint src = INVALID;
        if (!phys_reg_for_value(args.y, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_PRINT_I32;
        x86_inst_arg0[out_row] = src;
        x86_inst_arg1[out_row] = 0u;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_ALIAS)
    {
        uint dst = INVALID;
        uint src = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.x, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_MOV_R32_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = src;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_LOAD_LOCAL)
    {
        uint dst = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_LOAD_LOCAL_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.x;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_STORE_LOCAL)
    {
        uint src = INVALID;
        if (!phys_reg_for_value(args.y, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_STORE_LOCAL_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = src;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_LOAD_LOCAL_INDEX)
    {
        uint dst = INVALID;
        uint index = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, index))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_LOAD_LOCAL_INDEX_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.x;
        x86_inst_arg2[out_row] = index;
        return true;
    }

    if (op == X86_VINST_LOAD_PARAM_INDEX)
    {
        uint dst = INVALID;
        uint index = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, index))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_LOAD_PARAM_INDEX_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.x;
        x86_inst_arg2[out_row] = index;
        return true;
    }

    if (op == X86_VINST_LOAD_PARAM_SLOT)
    {
        uint dst = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_LOAD_PTR_SLOT_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.x;
        x86_inst_arg2[out_row] = args.y;
        return true;
    }

    if (op == X86_VINST_STORE_LOCAL_IMM)
    {
        x86_inst_kind[out_row] = X86_INST_V_STORE_LOCAL_IMM32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_FOR_ARRAY_BRANCH)
    {
        if (!target_valid(args.z, inst_count))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_FOR_ARRAY_BRANCH;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = selected_target(args.z, inst_count);
        return true;
    }

    if (op == X86_VINST_FOR_ARRAY_LOAD)
    {
        x86_inst_kind[out_row] = X86_INST_V_FOR_ARRAY_LOAD;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = args.z;
        return true;
    }

    if (op == X86_VINST_FOR_ARRAY_INC_JMP)
    {
        if (!target_valid(args.y, inst_count))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_FOR_ARRAY_INC_JMP;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = selected_target(args.y, inst_count);
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_FOR_INTERVAL_BRANCH)
    {
        if (!target_valid(args.z, inst_count))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_FOR_INTERVAL_BRANCH;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = selected_target(args.z, inst_count);
        return true;
    }

    if (op == X86_VINST_COPY_LOCAL)
    {
        x86_inst_kind[out_row] = X86_INST_V_COPY_LOCAL_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_RETURN)
    {
        uint src = INVALID;
        if (!phys_reg_for_value(args.x, inst_count, src))
            return false;
        uint owner_slot = x86_virtual_func_slot[row];
        uint main_slot = x86_func_meta[FUNC_META_MAIN_SLOT];
        x86_inst_kind[out_row] = owner_slot == main_slot ?
                                 X86_INST_V_RETURN_R32 :
                                 X86_INST_V_RETURN_FUNC_R32;
        x86_inst_arg0[out_row] = src;
        x86_inst_arg1[out_row] = 0u;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_STORE_RET_PTR)
    {
        uint src = INVALID;
        if (!phys_reg_for_value(args.x, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_STORE_RET_PTR_R32;
        x86_inst_arg0[out_row] = src;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_STORE_RET_PTR_IMM)
    {
        x86_inst_kind[out_row] = X86_INST_V_STORE_RET_PTR_IMM32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_MATCH_TAG_BRANCH)
    {
        if (!target_valid(args.w, inst_count))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_MATCH_TAG_BRANCH;
        x86_inst_arg0[out_row] = pack_u16_pair(args.x, args.z);
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = selected_target(args.w, inst_count);
        return true;
    }

    if (op == X86_VINST_COPY_AGG_RET)
    {
        x86_inst_kind[out_row] = X86_INST_V_COPY_AGG_RET;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = args.y;
        x86_inst_arg2[out_row] = args.z;
        return true;
    }

    if (op == X86_VINST_RETURN_VOID)
    {
        x86_inst_kind[out_row] = X86_INST_RET;
        x86_inst_arg0[out_row] = 0u;
        x86_inst_arg1[out_row] = 0u;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_BRANCH)
    {
        if (!target_valid(args.y, inst_count))
            return false;
        if (args.x == INVALID)
        {
            x86_inst_kind[out_row] = X86_INST_V_JMP;
            x86_inst_arg0[out_row] = selected_target(args.y, inst_count);
            x86_inst_arg1[out_row] = 0u;
            x86_inst_arg2[out_row] = 0u;
            return true;
        }

        uint cond = INVALID;
        if (!phys_reg_for_value(args.x, inst_count, cond))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_BRANCH_ZERO;
        x86_inst_arg0[out_row] = cond;
        x86_inst_arg1[out_row] = selected_target(args.y, inst_count);
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    uint inst_count = ok ? virtual_inst_count() : 0u;
    uint selected_count = ok ? selected_inst_count() : 0u;

    if (row == 0u)
    {
        uint entry_target = INVALID;
        bool entry_ok = ok && main_entry_target(inst_count, entry_target);
        select_status[0u] = entry_ok ? X86_SELECT_OK : 0u;
        select_status[1u] = entry_ok ? 0u :
                             (x86_func_first_virtual_row_status[1u] != 0u ?
                              x86_func_first_virtual_row_status[1u] :
                              (x86_virtual_regalloc_status[1u] == 0u ?
                              X86_ERR_SELECT :
                              x86_virtual_regalloc_status[1u]));
        select_status[2u] = entry_ok ? INVALID :
                             (x86_func_first_virtual_row_status[1u] != 0u ?
                              x86_func_first_virtual_row_status[2u] :
                              (x86_virtual_regalloc_status[1u] == 0u ?
                              x86_virtual_inst_status[2u] :
                              x86_virtual_regalloc_status[2u]));
        select_status[3u] = entry_ok ? selected_count : 0u;
        if (entry_ok)
        {
            x86_inst_kind[0u] = X86_INST_V_ENTRY_STACK_JMP;
            x86_inst_arg0[0u] = entry_target;
            x86_inst_arg1[0u] = entry_frame_size();
            x86_inst_arg2[0u] = 0u;
            x86_inst_kind[selected_count - 1u] = X86_INST_V_EXIT_ZERO;
            x86_inst_arg0[selected_count - 1u] = 0u;
            x86_inst_arg1[selected_count - 1u] = 0u;
            x86_inst_arg2[selected_count - 1u] = 0u;
        }
    }

    if (!ok || selected_count == 0u)
        return;

    if (row >= inst_count)
        return;

    if (!select_virtual_inst(row, inst_count))
        publish_error(row, x86_virtual_inst_record[row].z);
}
