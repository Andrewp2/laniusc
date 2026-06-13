// x86_64 virtual-instruction row bounds per function.
//
// Pareas avoids local full-array searches by materializing relation tables with
// bulk map/scatter operations. This pass scatters each virtual instruction row
// to its owning function with atomic min/max, producing O(1) row bounds for
// later function-local stages.

import atomics;
import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_next_call_step_count;
    uint regalloc_rows_per_chunk;
    uint regalloc_chunk_count;
    uint function_slot_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_func_slot_by_node;

RWStructuredBuffer<uint> x86_func_first_virtual_row;
RWStructuredBuffer<uint> x86_func_last_virtual_row;
RWStructuredBuffer<uint> x86_func_first_virtual_row_status;
RWStructuredBuffer<uint> x86_virtual_func_slot;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_FUNC_FIRST_VIRTUAL_ROW_OK = 1u;
static const uint X86_ERR_FUNC_FIRST_VIRTUAL_ROW = 18u;

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

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

void publish_status(bool ok, uint count)
{
    x86_func_first_virtual_row_status[0u] = ok ? X86_FUNC_FIRST_VIRTUAL_ROW_OK : 0u;
    x86_func_first_virtual_row_status[1u] = ok ? 0u :
                                            stage_status4_error_or(
                                                x86_virtual_inst_status,
                                                X86_ERR_FUNC_FIRST_VIRTUAL_ROW);
    x86_func_first_virtual_row_status[2u] = ok ? INVALID :
                                            stage_status4_detail_or(
                                                x86_virtual_inst_status,
                                                0u);
    x86_func_first_virtual_row_status[3u] = ok ? count : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    uint count = ok ? virtual_inst_count() : 0u;

    if (row == 0u)
        publish_status(ok, count);

    if (!ok || row >= count)
        return;

    x86_virtual_func_slot[row] = INVALID;

    uint node = x86_virtual_inst_record[row].x;
    if (!valid_node(node))
        return;

    uint fn_node = x86_node_func[node];
    if (!valid_node(fn_node))
        return;

    uint slot = x86_func_slot_by_node[fn_node];
    if (slot >= gParams.function_slot_capacity)
        return;

    x86_virtual_func_slot[row] = slot;
    atomic_u32_min(x86_func_first_virtual_row, slot, row);
    atomic_u32_max(x86_func_last_virtual_row, slot, row);
}
