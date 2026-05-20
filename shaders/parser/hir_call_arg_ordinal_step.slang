// Pointer-jump call-argument links to produce list roots and ordinal ranks.
//
// This is the Slang equivalent of Pareas' compute_depths/match-list style
// linked-list propagation. No call thread scans its subtree and no argument
// thread scans back through earlier nodes.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirCall;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_call_arg_owner_in;
StructuredBuffer<uint> hir_call_arg_link_in;
StructuredBuffer<uint> hir_call_arg_rank_in;

RWStructuredBuffer<uint> hir_call_arg_owner_out;
RWStructuredBuffer<uint> hir_call_arg_link_out;
RWStructuredBuffer<uint> hir_call_arg_rank_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirCall.uses_ll1 != 0u ? min(gHirCall.n, ll1_status[5u]) : gHirCall.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirCall.n)
        return;

    if (!valid_node(node))
    {
        hir_call_arg_owner_out[node] = INVALID;
        hir_call_arg_link_out[node] = INVALID;
        hir_call_arg_rank_out[node] = 0u;
        return;
    }

    uint owner = hir_call_arg_owner_in[node];
    uint link = hir_call_arg_link_in[node];
    uint rank = hir_call_arg_rank_in[node];

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        hir_call_arg_owner_out[node] = valid_node(owner) ? owner : INVALID;
        hir_call_arg_link_out[node] = INVALID;
        hir_call_arg_rank_out[node] = rank;
        return;
    }

    uint ancestor_owner = hir_call_arg_owner_in[link];
    uint ancestor_link = hir_call_arg_link_in[link];
    uint ancestor_rank = hir_call_arg_rank_in[link];
    uint resolved_owner = valid_node(ancestor_owner) ? ancestor_owner : INVALID;

    hir_call_arg_owner_out[node] = resolved_owner;
    hir_call_arg_rank_out[node] = rank + ancestor_rank;
    hir_call_arg_link_out[node] =
        valid_node(resolved_owner) || !valid_node(ancestor_link) ? INVALID : ancestor_link;
}
