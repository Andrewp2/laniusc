// Flag live virtual instruction rows that define scalar values.
//
// This is the current x86 intermediate-code optimization boundary. Liveness
// has already extended value-definition live ends through operand uses; this
// pass keeps side-effecting value definitions and pure value definitions with a
// later use, and lets later allocation/selection skip pure dead values.

import gpu_index;

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
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_live_end;
StructuredBuffer<uint> x86_virtual_liveness_status;

RWStructuredBuffer<uint> x86_virtual_value_def_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_LIVENESS_OK = 1u;

static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_LOAD_LOCAL = 13u;
static const uint X86_VINST_LOAD_LOCAL_INDEX = 15u;
static const uint X86_VINST_LOAD_PARAM_INDEX = 21u;
static const uint X86_VINST_LOAD_PARAM_SLOT = 26u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool upstream_ok()
{
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u &&
           x86_virtual_inst_status[3u] <= gParams.inst_capacity;
}

uint scanned_row_count()
{
    if (!upstream_ok())
        return 0u;
    uint count = virtual_inst_count();
    uint selected = count + 2u;
    if (selected < count)
        selected = 0xffffffffu;
    return min(selected, gParams.inst_capacity);
}

bool inst_has_value_def(uint4 inst, uint row)
{
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

bool liveness_ok(uint count)
{
    return x86_virtual_liveness_status[0u] == X86_VIRTUAL_LIVENESS_OK &&
           x86_virtual_liveness_status[1u] == 0u &&
           x86_virtual_liveness_status[3u] == count;
}

bool pure_value_def_op(uint op)
{
    return op == X86_VINST_IMM_I32 ||
           op == X86_VINST_PARAM ||
           op == X86_VINST_UNARY ||
           op == X86_VINST_BINARY ||
           op == X86_VINST_COMPARE ||
           op == X86_VINST_ALIAS ||
           op == X86_VINST_LOAD_LOCAL ||
           op == X86_VINST_LOAD_LOCAL_INDEX ||
           op == X86_VINST_LOAD_PARAM_INDEX ||
           op == X86_VINST_LOAD_PARAM_SLOT;
}

bool value_def_is_live(uint row, uint count, uint4 inst)
{
    if (!inst_has_value_def(inst, row))
        return false;
    if (!liveness_ok(count))
        return true;
    if (!pure_value_def_op(inst.z))
        return true;
    return x86_virtual_live_end[row] != INVALID && x86_virtual_live_end[row] > row;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint count = upstream_ok() ? virtual_inst_count() : 0u;
    uint scanned_count = scanned_row_count();
    if (row >= scanned_count)
        return;

    uint4 inst = row < count ? x86_virtual_inst_record[row] : uint4(INVALID, 0u, 0u, 0u);
    x86_virtual_value_def_flag[row] = row < count && value_def_is_live(row, count, inst) ? 1u : 0u;
}
