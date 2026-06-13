// Mark parser-owned HIR call arguments for compact semantic rows.
//
// This pass keeps argument discovery in the HIR record layer. It clears the
// dense row outputs and writes one prefix-scan flag per HIR node; the following
// scan/scatter passes publish compact call-argument rows.

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

RWStructuredBuffer<uint> call_arg_row_flag;
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

bool is_valid_call_arg_row(uint node, uint n)
{
    uint packed = hir_call_arg_parent_call[node];
    if (packed == INVALID)
        return false;

    uint call_node = hir_node_ordinal_node(packed);
    uint ordinal = hir_node_ordinal_ordinal(packed);
    if (!valid_node(call_node, n) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint count = hir_call_arg_count[call_node];
    return count != 0u && ordinal < count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    if (node >= n)
        return;

    call_arg_row_flag[node] = is_valid_call_arg_row(node, n) ? 1u : 0u;
    call_arg_row_node[node] = INVALID;
    call_arg_row_call_node[node] = INVALID;
    call_arg_row_ordinal[node] = INVALID;
    call_arg_row_start[node] = INVALID;
    call_arg_row_count[node] = 0u;
}
