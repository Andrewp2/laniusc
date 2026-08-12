// Pointer-jump a compact linked list to its owner while summing edge ranks.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirListRank;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;
StructuredBuffer<uint> list_owner_in;
StructuredBuffer<uint> list_link_in;
StructuredBuffer<uint> list_rank_in;
RWStructuredBuffer<uint> list_owner_out;
RWStructuredBuffer<uint> list_link_out;
RWStructuredBuffer<uint> list_rank_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirListRank.uses_status_count != 0u
        ? min(gHirListRank.n, tree_count_status[5u])
        : gHirListRank.n;
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
    if (row >= gHirListRank.n || row >= hir_list_rank_count[0u])
        return;

    uint node = hir_list_rank_node[row];
    if (!valid_node(node))
        return;

    uint owner = list_owner_in[node];
    uint link = list_link_in[node];
    uint rank = list_rank_in[node];
    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (valid_node(owner) || !valid_node(link) || link == node)
            break;

        rank += list_rank_in[link];
        uint ancestor_owner = list_owner_in[link];
        uint ancestor_link = list_link_in[link];
        if (valid_node(ancestor_owner))
        {
            owner = ancestor_owner;
            link = INVALID;
            break;
        }
        link = valid_node(ancestor_link) ? ancestor_link : INVALID;
    }

    list_owner_out[node] = valid_node(owner) ? owner : INVALID;
    list_link_out[node] = link;
    list_rank_out[node] = rank;
}
