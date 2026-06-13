// Count virtual-register operands per virtual instruction before compact scatter.

import gpu_index;
import bit_packing;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_use_edge_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;

RWStructuredBuffer<uint> x86_virtual_use_count;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;

static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_INTRINSIC = 7u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_LOOP = 11u;
static const uint X86_VINST_LOAD_LOCAL = 13u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_LOAD_LOCAL_INDEX = 15u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_VINST_LOAD_PARAM_INDEX = 21u;
static const uint X86_VINST_STORE_RET_PTR = 22u;
static const uint X86_VINST_STORE_LOCAL_INDEX = 30u;
static const uint X86_VINST_STORE_PARAM_INDEX = 32u;
static const uint X86_ARG_SCALAR = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    bool ok = x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
              x86_virtual_inst_status[1u] == 0u &&
              x86_virtual_inst_status[3u] <= gParams.inst_capacity;
    return ok ? min(x86_virtual_inst_status[3u], gParams.inst_capacity) : 0u;
}

uint mixed_arg_count(uint info)
{
    return info & 0xffu;
}

uint mixed_arg_kind(uint info, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u2_at_offset(info, 12u, ordinal);
    if (ordinal < 6u)
        return packed_u2_at_offset(info, 20u, ordinal - 4u);
    return 0u;
}

uint mixed_scalar_operand_count(uint row)
{
    uint info = x86_virtual_inst_args[row].w;
    uint count = 0u;
    uint arg_count = mixed_arg_count(info);
    if (arg_count > 0u && mixed_arg_kind(info, 0u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 1u && mixed_arg_kind(info, 1u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 2u && mixed_arg_kind(info, 2u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 3u && mixed_arg_kind(info, 3u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 4u && mixed_arg_kind(info, 4u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 5u && mixed_arg_kind(info, 5u) == X86_ARG_SCALAR) count += 1u;
    return count;
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
    if (op == X86_VINST_BINARY ||
        op == X86_VINST_COMPARE ||
        op == X86_VINST_STORE_LOCAL_INDEX ||
        op == X86_VINST_STORE_PARAM_INDEX)
        return 2u;
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = virtual_inst_count();
    if (row >= inst_count)
        return;

    uint4 inst = x86_virtual_inst_record[row];
    x86_virtual_use_count[row] =
        inst.x != INVALID && inst.z != 0u
            ? operand_count_for_row(row)
            : 0u;
}
