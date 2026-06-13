// Initialize x86_64 virtual-register liveness rows before operand atomics.
//
// This pass writes every virtual instruction row consumed by register
// allocation. The following operand pass only extends live_end with atomics, so
// it cannot race against row initialization.

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

RWStructuredBuffer<uint> x86_virtual_live_start;
RWStructuredBuffer<uint> x86_virtual_live_end;
RWStructuredBuffer<uint> x86_virtual_phys_reg;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;

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

bool has_value_def(uint row, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = virtual_inst_count();
    if (row >= inst_count)
        return;

    x86_virtual_phys_reg[row] = INVALID;

    if (has_value_def(row, inst_count))
    {
        x86_virtual_live_start[row] = row;
        x86_virtual_live_end[row] = row;
    }
    else
    {
        x86_virtual_live_start[row] = INVALID;
        x86_virtual_live_end[row] = INVALID;
    }
}
