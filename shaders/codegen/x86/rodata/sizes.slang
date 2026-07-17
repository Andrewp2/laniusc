// x86_64 read-only data sizing from compact string-literal rows.

import gpu_index;
import status;
import byte_packing;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirString { uint node; uint data_offset; uint decoded_len; uint file_id; };
StructuredBuffer<uint> compact_string_count;
StructuredBuffer<HirString> compact_strings;
StructuredBuffer<uint> x86_compact_executable_raw;

RWStructuredBuffer<uint> x86_rodata_size_by_node;
RWStructuredBuffer<uint> x86_rodata_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_RODATA_OK = 1u;
static const uint X86_ERR_RODATA_SIZE = 63u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint string_count = min(compact_string_count[0u], gParams.n_hir_nodes);

    if (row == 0u)
    {
        x86_rodata_status[0u] = X86_RODATA_OK;
        x86_rodata_status[1u] = 0u;
        x86_rodata_status[2u] = INVALID;
        x86_rodata_status[3u] = gParams.n_hir_nodes;
    }

    if (row >= string_count)
        return;
    HirString string_row = compact_strings[row];
    uint node = string_row.node < gParams.n_hir_nodes
                    ? x86_compact_executable_raw[string_row.node]
                    : INVALID;
    if (node < gParams.n_hir_nodes)
        x86_rodata_size_by_node[node] = string_row.decoded_len + 1u;
}
