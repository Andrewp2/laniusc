struct Params { uint n; uint uses_status_count; uint n_prefix_blocks; uint max_tree_leaf_base; };
ConstantBuffer<Params> gTree;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> tree_depth_link_in;
StructuredBuffer<uint> tree_depth_value_in;
RWStructuredBuffer<uint> tree_depth_link_out;
RWStructuredBuffer<uint> tree_depth_value_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 tid) { return tid.x + tid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gTree.uses_status_count != 0u ? min(gTree.n, tree_count_status[5u]) : gTree.n; }

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(tid);
    uint active = active_node_count();
    if (node >= active) return;
    uint link = tree_depth_link_in[node];
    uint depth = tree_depth_value_in[node];
    if (link == INVALID || link >= active)
    {
        tree_depth_link_out[node] = INVALID;
        tree_depth_value_out[node] = depth;
        return;
    }
    tree_depth_link_out[node] = tree_depth_link_in[link];
    tree_depth_value_out[node] = depth + tree_depth_value_in[link];
}
