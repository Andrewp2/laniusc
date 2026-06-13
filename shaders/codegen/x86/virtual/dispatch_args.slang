// Build indirect dispatch arguments from GPU-resident virtual instruction count.

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

StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_func_meta;

RWStructuredBuffer<uint> active_function_dispatch_args;
RWStructuredBuffer<uint> active_virtual_inst_dispatch_args;
RWStructuredBuffer<uint> active_virtual_next_call_dispatch_args;
RWStructuredBuffer<uint> active_selected_inst_dispatch_args;
RWStructuredBuffer<uint> active_selected_scan_block_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint FUNC_META_FUNC_COUNT = 0u;

uint virtual_inst_count()
{
    bool ok = x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
              x86_virtual_inst_status[1u] == 0u &&
              x86_virtual_inst_status[3u] <= gParams.inst_capacity;
    return ok ? min(x86_virtual_inst_status[3u], gParams.inst_capacity) : 0u;
}

uint saturating_add_u32(uint a, uint b)
{
    uint sum = a + b;
    return sum < a ? 0xffffffffu : sum;
}

void write_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = 1u;
}

void write_scan_block_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint active_blocks = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    write_dispatch_args(args, active_blocks);
}

uint scan_step_for_index(uint step_i)
{
    if (step_i == 0u)
        return 0u;
    return 1u << min(step_i - 1u, 31u);
}

void write_indexed_dispatch_args(RWStructuredBuffer<uint> args, uint step_i, uint active_records)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    uint base = step_i * 3u;
    args[base + 0u] = min(groups, MAX_GROUPS_X);
    args[base + 1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[base + 2u] = 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.y != 0u || tid.z != 0u)
        return;

    uint count = virtual_inst_count();
    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.function_slot_capacity);
    uint item_i = tid.x;
    if (item_i < gParams.virtual_next_call_step_count)
    {
        uint scan_step = scan_step_for_index(item_i);
        uint active_rows = (scan_step == 0u || scan_step < count) ? count : 1u;
        write_indexed_dispatch_args(active_virtual_next_call_dispatch_args, item_i, active_rows);
    }

    if (tid.x != 0u)
        return;

    uint selected = min(gParams.inst_capacity, saturating_add_u32(count, 2u));
    write_dispatch_args(active_function_dispatch_args, func_count);
    write_dispatch_args(active_virtual_inst_dispatch_args, count);
    write_dispatch_args(active_selected_inst_dispatch_args, selected);
    write_scan_block_dispatch_args(active_selected_scan_block_dispatch_args, selected);
}
