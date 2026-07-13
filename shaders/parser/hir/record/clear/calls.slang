// Clear call and member HIR metadata before dense semantic publish passes.
//
// This keeps non-semantic parse-tree rows invalid while letting call/member
// producers run only over compact HIR rows.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gClear;

StructuredBuffer<uint> tree_count_status;

RWStructuredBuffer<uint> hir_member_receiver_node;
RWStructuredBuffer<uint> hir_member_receiver_token;
RWStructuredBuffer<uint> hir_member_name_token;
RWStructuredBuffer<uint> hir_call_callee_node;
RWStructuredBuffer<uint> hir_call_callee_path_node;
RWStructuredBuffer<uint> hir_call_parent_by_callee;
RWStructuredBuffer<uint> hir_call_context_stmt_node;
RWStructuredBuffer<uint> hir_call_arg_start;
RWStructuredBuffer<uint> hir_call_arg_end;
RWStructuredBuffer<uint> hir_call_arg_count;
RWStructuredBuffer<uint> hir_call_arg_parent_call;
RWStructuredBuffer<uint> hir_call_arg_ordinal;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gClear.uses_status_count != 0u ? min(gClear.n, tree_count_status[5u]) : gClear.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_node_count())
        return;

    hir_member_receiver_node[node] = INVALID;
    hir_member_receiver_token[node] = INVALID;
    hir_member_name_token[node] = INVALID;

    hir_call_callee_node[node] = INVALID;
    hir_call_callee_path_node[node] = INVALID;
    hir_call_parent_by_callee[node] = INVALID;
    hir_call_context_stmt_node[node] = INVALID;
    hir_call_arg_start[node] = INVALID;
    hir_call_arg_end[node] = INVALID;
    hir_call_arg_count[node] = 0u;
    hir_call_arg_parent_call[node] = INVALID;
    hir_call_arg_ordinal[node] = INVALID;
}
