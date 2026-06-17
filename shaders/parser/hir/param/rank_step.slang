// Pointer-jump function-parameter links to produce owning functions.
//
// Parameter ordinals are assigned later from compact scanned parameter rows.
// The rank buffers remain in this pass only as temporary ping-pong state; the
// published parser-visible ordinal is overwritten by param/id_apply.slang.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_param_owner_in;
StructuredBuffer<uint> hir_param_link_in;
StructuredBuffer<uint> hir_param_rank_in;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;

RWStructuredBuffer<uint> hir_param_owner_out;
RWStructuredBuffer<uint> hir_param_link_out;
RWStructuredBuffer<uint> hir_param_rank_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirParam.uses_status_count != 0u ? min(gHirParam.n, tree_count_status[5u]) : gHirParam.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= gHirParam.n || row >= hir_list_rank_count[0u])
        return;

    uint node = hir_list_rank_node[row];
    if (node >= gHirParam.n)
        return;

    if (!valid_node(node))
    {
        hir_param_owner_out[node] = INVALID;
        hir_param_link_out[node] = INVALID;
        hir_param_rank_out[node] = 0u;
        return;
    }

    uint owner = hir_param_owner_in[node];
    uint link = hir_param_link_in[node];
    uint rank = hir_param_rank_in[node];

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        hir_param_owner_out[node] = valid_node(owner) ? owner : INVALID;
        hir_param_link_out[node] = INVALID;
        hir_param_rank_out[node] = rank;
        return;
    }

    uint ancestor_owner = hir_param_owner_in[link];
    uint ancestor_link = hir_param_link_in[link];
    uint ancestor_rank = hir_param_rank_in[link];
    uint resolved_owner = valid_node(ancestor_owner) ? ancestor_owner : INVALID;

    hir_param_owner_out[node] = resolved_owner;
    hir_param_rank_out[node] = rank + ancestor_rank;
    hir_param_link_out[node] =
        valid_node(resolved_owner) || !valid_node(ancestor_link) ? INVALID : ancestor_link;
}
