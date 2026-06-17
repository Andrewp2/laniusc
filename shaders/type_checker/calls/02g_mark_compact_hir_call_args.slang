// Mark parser-owned HIR call argument segments for compact semantic rows.
//
// This pass keeps argument discovery in the HIR record layer. It clears the
// dense row outputs and writes each call node's argument count as the scan
// input; the following scan/scatter passes publish compact per-call argument
// rows where row_start[call] + ordinal is stable even when nested call rows
// interleave in source/HIR order.

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

RWStructuredBuffer<uint> call_arg_row_scan_input;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    if (node >= n)
        return;

    call_arg_row_scan_input[node] =
        hir_kind[node] == HIR_CALL_EXPR ? hir_call_arg_count[node] : 0u;
    call_arg_row_node[node] = INVALID;
    call_arg_row_call_node[node] = INVALID;
    call_arg_row_ordinal[node] = INVALID;
    call_arg_row_start[node] = INVALID;
    call_arg_row_count[node] = 0u;
}
