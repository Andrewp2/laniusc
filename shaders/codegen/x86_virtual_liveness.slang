// x86_64 virtual-register liveness extension over virtual instruction operands.
//
// Pareas register allocation consumes the instruction stream directly rather
// than materializing a separate use-edge array. This pass follows that shape:
// each virtual instruction validates its operand rows and atomically extends
// the referenced value's live_end.

import gpu_index;
import atomics;
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

RWStructuredBuffer<uint> x86_virtual_live_end;
RWStructuredBuffer<uint> x86_virtual_liveness_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_OPERANDS = 4u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_LIVENESS_OK = 1u;
static const uint X86_ERR_VIRTUAL_LIVENESS = 14u;

static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_INTRINSIC = 7u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_LOOP = 11u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_LOAD_LOCAL_INDEX = 15u;
static const uint X86_VINST_STORE_LOCAL_IMM = 16u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_VINST_LOAD_PARAM_INDEX = 21u;
static const uint X86_VINST_STORE_RET_PTR = 22u;
static const uint X86_ARG_SCALAR = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool upstream_ok(uint inst_count)
{
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u &&
           x86_virtual_inst_status[3u] == inst_count &&
           inst_count <= gParams.inst_capacity;
}

bool has_value_def(uint row, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

uint mixed_arg_count(uint info)
{
    return info & 0xffu;
}

uint mixed_arg_kind(uint info, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u2_at_offset(info, 12u, ordinal);
    return 0u;
}

uint mixed_arg_payload(uint row, uint ordinal)
{
    uint4 args = x86_virtual_inst_args[row];
    uint payload_row = args.z;
    if (payload_row == INVALID || payload_row >= virtual_inst_count() || ordinal >= 4u)
        return INVALID;
    return x86_virtual_inst_args[payload_row][ordinal];
}

uint mixed_scalar_operand_count(uint row)
{
    uint4 args = x86_virtual_inst_args[row];
    uint info = args.w;
    uint count = 0u;
    uint arg_count = mixed_arg_count(info);
    [unroll]
    for (uint ordinal = 0u; ordinal < 4u; ordinal += 1u)
    {
        if (ordinal < arg_count && mixed_arg_kind(info, ordinal) == X86_ARG_SCALAR)
            count += 1u;
    }
    return count;
}

uint mixed_scalar_operand_at(uint row, uint slot)
{
    uint4 args = x86_virtual_inst_args[row];
    uint info = args.w;
    uint seen = 0u;
    uint arg_count = mixed_arg_count(info);
    [unroll]
    for (uint ordinal = 0u; ordinal < 4u; ordinal += 1u)
    {
        if (ordinal < arg_count && mixed_arg_kind(info, ordinal) == X86_ARG_SCALAR)
        {
            if (seen == slot)
                return mixed_arg_payload(row, ordinal);
            seen += 1u;
        }
    }
    return INVALID;
}

uint operand_count_for_row(uint row)
{
    uint op = x86_virtual_inst_record[row].z;
    uint4 args = x86_virtual_inst_args[row];
    if (op == X86_VINST_UNARY ||
        op == X86_VINST_ALIAS ||
        op == X86_VINST_RETURN ||
        op == X86_VINST_STORE_LOCAL ||
        op == X86_VINST_LOAD_LOCAL_INDEX ||
        op == X86_VINST_LOAD_PARAM_INDEX ||
        op == X86_VINST_STORE_RET_PTR)
        return 1u;
    if (op == X86_VINST_BRANCH ||
        op == X86_VINST_LOOP)
        return args.x == INVALID ? 0u : 1u;
    if (op == X86_VINST_INTRINSIC)
        return 1u;
    if (op == X86_VINST_CALL_MIXED)
        return mixed_scalar_operand_count(row);
    if (op == X86_VINST_BINARY || op == X86_VINST_COMPARE)
        return 2u;
    return 0u;
}

uint operand_at(uint row, uint slot)
{
    uint4 args = x86_virtual_inst_args[row];
    uint op = x86_virtual_inst_record[row].z;
    if (op == X86_VINST_UNARY)
        return slot == 0u ? args.y : INVALID;
    if (op == X86_VINST_BINARY || op == X86_VINST_COMPARE)
    {
        if (slot == 0u) return args.y;
        if (slot == 1u) return args.z;
        return INVALID;
    }
    if (op == X86_VINST_CALL_MIXED)
        return mixed_scalar_operand_at(row, slot);
    if (op == X86_VINST_INTRINSIC)
        return slot == 0u ? args.y : INVALID;
    if (op == X86_VINST_ALIAS ||
        op == X86_VINST_RETURN ||
        op == X86_VINST_STORE_LOCAL ||
        op == X86_VINST_LOAD_LOCAL_INDEX ||
        op == X86_VINST_LOAD_PARAM_INDEX ||
        op == X86_VINST_STORE_RET_PTR ||
        op == X86_VINST_BRANCH ||
        op == X86_VINST_LOOP)
        return slot == 0u ? ((op == X86_VINST_STORE_LOCAL ||
                              op == X86_VINST_LOAD_LOCAL_INDEX ||
                              op == X86_VINST_LOAD_PARAM_INDEX) ? args.y : args.x) : INVALID;
    return INVALID;
}

uint pack_error_extra(uint op, uint slot, uint operand, uint inst_count)
{
    uint operand_op = operand < inst_count ? x86_virtual_inst_record[operand].z : 0xffu;
    return ((slot & 0x03u) << 30u) |
           ((op & 0xffu) << 22u) |
           ((operand_op & 0xffu) << 14u) |
           (operand & 0x00003fffu);
}

bool extend_operand_live_end(uint row, uint inst_count, uint op, uint slot)
{
    uint operand = operand_at(row, slot);
    if (!has_value_def(operand, inst_count))
    {
        publish_stage_error_min_detail_extra4(
            x86_virtual_liveness_status,
            X86_ERR_VIRTUAL_LIVENESS,
            row,
            pack_error_extra(op, slot, operand, inst_count));
        return false;
    }
    atomic_u32_max(x86_virtual_live_end, operand, row);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = virtual_inst_count();
    bool ok = upstream_ok(inst_count);

    if (row == 0u)
    {
        write_stage_status4_from_result(
            x86_virtual_liveness_status,
            ok,
            X86_VIRTUAL_LIVENESS_OK,
            INVALID,
            X86_ERR_VIRTUAL_LIVENESS,
            x86_virtual_inst_status[1u],
            inst_count,
            x86_virtual_inst_status[2u],
            inst_count);
    }

    if (!ok || row >= inst_count)
        return;

    uint4 inst = x86_virtual_inst_record[row];
    if (inst.x == INVALID || inst.z == 0u)
        return;

    uint operand_count = operand_count_for_row(row);
    if (operand_count >= 1u && !extend_operand_live_end(row, inst_count, inst.z, 0u))
        return;
    if (operand_count >= 2u && !extend_operand_live_end(row, inst_count, inst.z, 1u))
        return;
    if (operand_count >= 3u && !extend_operand_live_end(row, inst_count, inst.z, 2u))
        return;
    if (operand_count >= 4u && !extend_operand_live_end(row, inst_count, inst.z, 3u))
        return;
}
