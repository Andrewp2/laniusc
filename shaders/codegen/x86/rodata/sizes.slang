// x86_64 read-only data sizing for parser-owned string literal HIR rows.

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

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_string_decoded_len;

RWStructuredBuffer<uint> x86_rodata_size_by_node;
RWStructuredBuffer<uint> x86_rodata_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint X86_RODATA_OK = 1u;
static const uint X86_ERR_RODATA_SIZE = 63u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

uint expr_form(uint node)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        HIR_EXPR_RECORD_STRIDE,
        HIR_EXPR_RECORD_FORM,
        0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint active_count = active_hir_node_count();

    if (node == 0u)
    {
        x86_rodata_status[0u] = X86_RODATA_OK;
        x86_rodata_status[1u] = 0u;
        x86_rodata_status[2u] = INVALID;
        x86_rodata_status[3u] = active_count;
    }

    if (node >= active_count)
        return;

    uint size = 0u;
    if (expr_form(node) == HIR_EXPR_STRING)
    {
        size = hir_string_decoded_len[node] + 1u;
    }

    x86_rodata_size_by_node[node] = size;
}
