// Precompute whether each virtual value interval crosses a fixed-register
// barrier. Register allocation consumes this record instead of looking through
// the next-barrier scan from its sequential per-function loop.

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
StructuredBuffer<uint> x86_virtual_live_start;
StructuredBuffer<uint> x86_virtual_live_end;
StructuredBuffer<uint> x86_virtual_liveness_status;
StructuredBuffer<uint> x86_virtual_next_call_a;
StructuredBuffer<uint> x86_virtual_next_call_b;
StructuredBuffer<uint> x86_virtual_next_call_status;

RWStructuredBuffer<uint> x86_virtual_spans_fixed_barrier;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_LIVENESS_OK = 1u;
static const uint X86_VIRTUAL_NEXT_CALLS_OK = 1u;

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
           x86_virtual_liveness_status[0u] == X86_VIRTUAL_LIVENESS_OK &&
           x86_virtual_liveness_status[1u] == 0u &&
           x86_virtual_liveness_status[3u] == inst_count &&
           x86_virtual_next_call_status[0u] == X86_VIRTUAL_NEXT_CALLS_OK &&
           x86_virtual_next_call_status[1u] == 0u &&
           x86_virtual_next_call_status[3u] == inst_count &&
           inst_count <= gParams.inst_capacity;
}

bool inst_has_value_def(uint4 inst, uint row)
{
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

uint ceil_log2_u32(uint value)
{
    if (value <= 1u)
        return 0u;
    uint x = value - 1u;
    uint result = 0u;
    if (x >= 0x10000u)
    {
        x >>= 16u;
        result += 16u;
    }
    if (x >= 0x100u)
    {
        x >>= 8u;
        result += 8u;
    }
    if (x >= 0x10u)
    {
        x >>= 4u;
        result += 4u;
    }
    if (x >= 0x4u)
    {
        x >>= 2u;
        result += 2u;
    }
    if (x >= 0x2u)
        result += 1u;
    return result + 1u;
}

bool final_next_call_buffer_is_a(uint inst_count)
{
    return (ceil_log2_u32(inst_count) & 1u) == 0u;
}

uint virtual_next_call_row(uint row, uint inst_count, bool final_next_call_buffer_is_a_value)
{
    if (row >= inst_count)
        return INVALID;
    return final_next_call_buffer_is_a_value
               ? x86_virtual_next_call_a[row]
               : x86_virtual_next_call_b[row];
}

uint next_barrier_after_row(uint row, uint inst_count, bool final_next_call_buffer_is_a_value)
{
    if (row >= inst_count)
        return INVALID;
    uint next = virtual_next_call_row(row, inst_count, final_next_call_buffer_is_a_value);
    if (next == row)
    {
        uint right_row = row + 1u;
        next = right_row < inst_count
            ? virtual_next_call_row(right_row, inst_count, final_next_call_buffer_is_a_value)
            : INVALID;
    }
    return next;
}

bool interval_strictly_contains(uint start, uint end, uint point)
{
    return point != INVALID && start < point && point < end;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = virtual_inst_count();
    bool ok = upstream_ok(inst_count);

    if (row >= inst_count)
        return;

    uint spans = 0u;
    uint4 inst = x86_virtual_inst_record[row];
    uint start = x86_virtual_live_start[row];
    uint end = x86_virtual_live_end[row];
    if (ok &&
        inst_has_value_def(inst, row) &&
        start != INVALID &&
        end != INVALID &&
        start <= end &&
        end - start > 1u)
    {
        bool final_is_a = final_next_call_buffer_is_a(inst_count);
        uint next = next_barrier_after_row(row, inst_count, final_is_a);
        spans = interval_strictly_contains(start, end, next) ? 1u : 0u;
    }

    x86_virtual_spans_fixed_barrier[row] = spans;
}
