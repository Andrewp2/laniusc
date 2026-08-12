// Follow a bounded run of path-segment predecessor links per dispatch.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirPath;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_path_segment_owner_in;
StructuredBuffer<uint> hir_path_segment_link_in;
StructuredBuffer<uint> hir_path_segment_rank_in;
RWStructuredBuffer<uint> hir_path_segment_owner_out;
RWStructuredBuffer<uint> hir_path_segment_link_out;
RWStructuredBuffer<uint> hir_path_segment_rank_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gHirPath.uses_status_count != 0u ? min(gHirPath.n, tree_count_status[5u]) : gHirPath.n; }
bool valid_node(uint node) { return node != INVALID && node < active_node_count(); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirPath.n)
        return;

    uint owner = hir_path_segment_owner_in[node];
    uint link = hir_path_segment_link_in[node];
    uint rank = hir_path_segment_rank_in[node];
    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        hir_path_segment_owner_out[node] = valid_node(owner) ? owner : INVALID;
        hir_path_segment_link_out[node] = INVALID;
        hir_path_segment_rank_out[node] = rank;
        return;
    }

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (valid_node(owner) || !valid_node(link) || link == node)
            break;
        rank += hir_path_segment_rank_in[link];
        uint ancestor_owner = hir_path_segment_owner_in[link];
        uint ancestor_link = hir_path_segment_link_in[link];
        if (valid_node(ancestor_owner))
        {
            owner = ancestor_owner;
            link = INVALID;
            break;
        }
        link = valid_node(ancestor_link) ? ancestor_link : INVALID;
    }
    hir_path_segment_owner_out[node] = valid_node(owner) ? owner : INVALID;
    hir_path_segment_rank_out[node] = rank;
    hir_path_segment_link_out[node] = link;
}
