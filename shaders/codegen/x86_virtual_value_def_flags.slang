// Flag virtual instruction rows that define scalar values.

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

RWStructuredBuffer<uint> x86_virtual_value_def_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint count = upstream_ok() ? virtual_inst_count() : 0u;
    uint scanned_count = scanned_row_count();
    if (row >= scanned_count)
        return;

    x86_virtual_value_def_flag[row] =
        row < count && inst_has_value_def(x86_virtual_inst_record[row], row) ? 1u : 0u;
}
