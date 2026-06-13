// Scatter compact parser-owned HIR call-argument rows.
//
// Input flags have already been prefix-scanned, so each argument row writes to
// one dense row. Per-call start/count records let semantic consumers lookup an
// argument by `(call_node, ordinal)` without reading the old four-slot table.

import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> call_arg_row_flag;
StructuredBuffer<uint> call_arg_row_prefix;

RWStructuredBuffer<uint> call_arg_row_node;
RWStructuredBuffer<uint> call_arg_row_call_node;
RWStructuredBuffer<uint> call_arg_row_ordinal;
RWStructuredBuffer<uint> call_arg_row_start;
RWStructuredBuffer<uint> call_arg_row_count;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node, uint n)
{
    return node != INVALID && node < n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    if (node >= n || call_arg_row_flag[node] == 0u)
        return;

    uint row = call_arg_row_prefix[node];
    if (row >= n)
        return;

    uint packed = hir_call_arg_parent_call[node];
    uint call_node = hir_node_ordinal_node(packed);
    uint ordinal = hir_node_ordinal_ordinal(packed);
    if (!valid_node(call_node, n) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint count = hir_call_arg_count[call_node];
    if (count == 0u || ordinal >= count)
        return;

    call_arg_row_node[row] = node;
    call_arg_row_call_node[row] = call_node;
    call_arg_row_ordinal[row] = ordinal;

    if (ordinal == 0u)
    {
        call_arg_row_start[call_node] = row;
        call_arg_row_count[call_node] = count;
    }
}
