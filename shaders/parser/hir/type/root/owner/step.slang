// Follow a bounded run of type-root links per dispatch, for the compacted type
// nodes only. Every other node keeps the record its init pass seeded into both
// ping-pong buffers.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirType;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;
StructuredBuffer<uint> hir_type_root_link_in;
StructuredBuffer<uint> hir_type_root_owner_in;
RWStructuredBuffer<uint> hir_type_root_link_out;
RWStructuredBuffer<uint> hir_type_root_owner_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

uint active_node_count()
{
    return gHirType.uses_status_count != 0u
        ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = tid.x + tid.y * MAX_GROUPS_X * WG_SIZE;
    if (row >= gHirType.n || row >= hir_list_rank_count[0u]) return;
    uint node = hir_list_rank_node[row];
    uint active = active_node_count();
    if (node >= active) return;
    uint link = hir_type_root_link_in[node];
    uint owner = hir_type_root_owner_in[node];
    for (uint hop = 0u; hop < LINKS_PER_STEP && link < active; ++hop)
    {
        uint ancestor_owner = hir_type_root_owner_in[link];
        if (ancestor_owner < active) owner = ancestor_owner;
        uint ancestor_link = hir_type_root_link_in[link];
        link = ancestor_link < active ? ancestor_link : INVALID;
    }
    hir_type_root_link_out[node] = link;
    hir_type_root_owner_out[node] = owner;
}
