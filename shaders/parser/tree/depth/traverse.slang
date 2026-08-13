// Compute raw parse-tree depth with one independent parent-chain traversal per
// node. This is the same execution shape as a BVH traversal: lanes retain their
// own traversal state and finish without global pointer-jump rounds.

struct Params { uint n; uint uses_status_count; uint n_prefix_blocks; uint max_tree_leaf_base; };
ConstantBuffer<Params> gTree;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
RWStructuredBuffer<uint> tree_depth_value_a;
RWStructuredBuffer<uint> tree_depth_status;

static const uint INVALID = 0xffffffffu;
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
    while (ancestor != INVALID)
    {
        // A valid tree reaches INVALID in at most `active` hops. Checking both
        // the index and hop count turns malformed links and cycles into an
        // internal invariant failure instead of an unbounded GPU traversal.
        if (!valid_node(ancestor, active) || depth == active)
        {
            InterlockedMax(tree_depth_status[0u], node + 1u);
            tree_depth_value_a[node] = 0u;
            return;
        }
        depth += 1u;
        ancestor = parent[ancestor];
    }
    tree_depth_value_a[node] = depth;
}
