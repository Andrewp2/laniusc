// Build register-allocation indirect dispatch arguments from GPU-resident
// function-span metadata.

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
StructuredBuffer<uint> x86_virtual_value_def_status;
RWStructuredBuffer<uint> x86_func_meta;

RWStructuredBuffer<uint> active_virtual_regalloc_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_VALUE_DEFS_OK = 1u;
static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint FUNC_META_REGALLOC_ACTIVE_CHUNKS = 6u;
static const uint FUNC_META_REGALLOC_RECORDED_CHUNKS = 7u;

uint virtual_inst_count()
{
    bool ok = x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
              x86_virtual_inst_status[1u] == 0u &&
              x86_virtual_inst_status[3u] <= gParams.inst_capacity;
    return ok ? min(x86_virtual_inst_status[3u], gParams.inst_capacity) : 0u;
}

uint value_def_count(uint inst_count)
{
    bool ok = x86_virtual_value_def_status[0u] == X86_VIRTUAL_VALUE_DEFS_OK &&
              x86_virtual_value_def_status[1u] == 0u &&
              x86_virtual_value_def_status[3u] <= inst_count;
    return ok ? x86_virtual_value_def_status[3u] : 0u;
}

void write_indexed_dispatch_args_allow_zero(RWStructuredBuffer<uint> args, uint step_i, uint active_records)
{
    uint base = step_i * 3u;
    if (active_records == 0u)
    {
        args[base + 0u] = 0u;
        args[base + 1u] = 0u;
        args[base + 2u] = 0u;
        return;
    }

    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
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

    uint item_i = tid.x;
    if (item_i >= 2u || gParams.regalloc_chunk_count != 2u)
        return;

    uint count = virtual_inst_count();
    uint value_defs = value_def_count(count);
    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.function_slot_capacity);
    if (item_i == 0u)
    {
        x86_func_meta[FUNC_META_REGALLOC_ACTIVE_CHUNKS] = 2u;
        x86_func_meta[FUNC_META_REGALLOC_RECORDED_CHUNKS] = 2u;
    }

    uint active_functions = item_i == 0u ? 1u : (value_defs == 0u ? 0u : func_count);
    write_indexed_dispatch_args_allow_zero(
        active_virtual_regalloc_dispatch_args,
        item_i,
        active_functions);
}
