// Compact scalar-value virtual instruction rows for register allocation.

import gpu_index;
import prefix_scan;
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
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_value_def_flag;
StructuredBuffer<uint> x86_virtual_value_def_scan_local_prefix;
StructuredBuffer<uint> x86_virtual_value_def_scan_block_prefix;

RWStructuredBuffer<uint> x86_virtual_value_def_row;
RWStructuredBuffer<uint> x86_virtual_value_def_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_VALUE_DEFS_OK = 1u;
static const uint X86_ERR_VIRTUAL_VALUE_DEFS = 23u;

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

bool inst_has_value_def(uint4 inst, uint row)
{
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

uint scanned_prefix_for_row(uint row)
{
    return global_exclusive_prefix(
        row,
        WG_SIZE,
        x86_virtual_value_def_scan_local_prefix,
        x86_virtual_value_def_scan_block_prefix);
}

uint value_def_total(uint inst_count)
{
    if (inst_count == 0u)
        return 0u;
    uint last_row = inst_count - 1u;
    return scanned_prefix_for_row(last_row) + x86_virtual_value_def_flag[last_row];
}

void publish_status(bool ok, uint total)
{
    x86_virtual_value_def_status[0u] = ok ? X86_VIRTUAL_VALUE_DEFS_OK : 0u;
    x86_virtual_value_def_status[1u] = ok ? 0u :
                                         stage_status4_error_or(
                                             x86_virtual_inst_status,
                                             X86_ERR_VIRTUAL_VALUE_DEFS);
    x86_virtual_value_def_status[2u] = ok ? INVALID :
                                         stage_status4_detail_or(
                                             x86_virtual_inst_status,
                                             0u);
    x86_virtual_value_def_status[3u] = ok ? total : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint count = upstream_ok() ? virtual_inst_count() : 0u;
    uint total = upstream_ok() ? value_def_total(count) : 0u;
    bool ok = upstream_ok() && total <= gParams.inst_capacity;

    if (row == 0u)
        publish_status(ok, total);

    if (!ok || row >= count || x86_virtual_value_def_flag[row] == 0u)
        return;

    uint4 inst = x86_virtual_inst_record[row];
    if (!inst_has_value_def(inst, row))
        return;

    uint ordinal = scanned_prefix_for_row(row);
    if (ordinal >= gParams.inst_capacity)
        return;

    x86_virtual_value_def_row[ordinal] = row;
}
