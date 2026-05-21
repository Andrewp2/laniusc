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
RWStructuredBuffer<uint> x86_func_meta;

RWStructuredBuffer<uint> active_virtual_regalloc_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint FUNC_META_MAX_VIRTUAL_FUNC_ROWS = 5u;
static const uint FUNC_META_REGALLOC_ACTIVE_CHUNKS = 6u;
static const uint FUNC_META_REGALLOC_RECORDED_CHUNKS = 7u;

uint virtual_inst_count()
{
    bool ok = x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
              x86_virtual_inst_status[1u] == 0u &&
              x86_virtual_inst_status[3u] <= gParams.inst_capacity;
    return ok ? min(x86_virtual_inst_status[3u], gParams.inst_capacity) : 0u;
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
    if (item_i >= gParams.regalloc_chunk_count)
        return;

    uint count = virtual_inst_count();
    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.function_slot_capacity);
    uint max_func_span = min(x86_func_meta[FUNC_META_MAX_VIRTUAL_FUNC_ROWS], count);
    uint rows_per_chunk = max(gParams.regalloc_rows_per_chunk, 1u);
    uint needed_chunks = max(1u, (max_func_span + rows_per_chunk - 1u) / rows_per_chunk);
    uint active_chunks = min(needed_chunks, gParams.regalloc_chunk_count);
    if (item_i == 0u)
    {
        x86_func_meta[FUNC_META_REGALLOC_ACTIVE_CHUNKS] = needed_chunks;
        x86_func_meta[FUNC_META_REGALLOC_RECORDED_CHUNKS] = gParams.regalloc_chunk_count;
    }

    uint chunk_start = item_i * rows_per_chunk;
    uint active_functions = item_i == 0u
        ? max(func_count, 1u)
        : (chunk_start < max_func_span ? func_count : 0u);
    write_indexed_dispatch_args_allow_zero(
        active_virtual_regalloc_dispatch_args,
        item_i,
        active_functions);
}
