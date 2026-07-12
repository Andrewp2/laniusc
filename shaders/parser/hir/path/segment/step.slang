// Pointer-jump path segment predecessor links to canonical owners and ordinals.

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

    uint ancestor_owner = hir_path_segment_owner_in[link];
    uint ancestor_link = hir_path_segment_link_in[link];
    hir_path_segment_owner_out[node] = valid_node(ancestor_owner) ? ancestor_owner : INVALID;
    hir_path_segment_rank_out[node] = rank + hir_path_segment_rank_in[link];
    hir_path_segment_link_out[node] = valid_node(ancestor_owner) || !valid_node(ancestor_link)
        ? INVALID : ancestor_link;
}
