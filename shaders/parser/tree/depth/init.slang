// Seed raw parse-tree depth with a bounded local parent walk before global
// pointer jumping. One lane owns one node; no lane walks the whole tree.

struct Params { uint n; uint uses_status_count; uint n_prefix_blocks; uint max_tree_leaf_base; };
ConstantBuffer<Params> gTree;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
RWStructuredBuffer<uint> tree_depth_link_a;
RWStructuredBuffer<uint> tree_depth_value_a;

static const uint INVALID = 0xffffffffu;
static const uint LOCAL_SPAN = 32u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 tid) { return tid.x + tid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gTree.uses_status_count != 0u ? min(gTree.n, tree_count_status[5u]) : gTree.n; }
bool valid_node(uint node, uint active) { return node != INVALID && node < active; }

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(tid);
    uint active = active_node_count();
    if (node >= active) return;

    uint ancestor = parent[node];
    uint depth = 0u;
    for (uint hop = 0u; hop < LOCAL_SPAN; ++hop)
    {
        if (!valid_node(ancestor, active)) break;
        depth += 1u;
        if (hop + 1u == LOCAL_SPAN)
        {
            tree_depth_link_a[node] = ancestor;
            tree_depth_value_a[node] = depth;
            return;
        }
        ancestor = parent[ancestor];
    }
    tree_depth_link_a[node] = INVALID;
    tree_depth_value_a[node] = depth;
}
