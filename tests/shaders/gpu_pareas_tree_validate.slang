import tree_pareas;

static const uint TEST_COUNT = 16u;
static const uint INVALID = 0xffffffffu;

StructuredBuffer<uint> parent_in;
StructuredBuffer<uint> prev_sibling_in;
StructuredBuffer<uint> next_sibling_in;
StructuredBuffer<uint> remove_mark_in;
StructuredBuffer<uint> list_link_in;
StructuredBuffer<uint> friend_seed_in;

RWStructuredBuffer<uint> depth_out;
RWStructuredBuffer<uint> root_out;
RWStructuredBuffer<uint> unmarked_parent_out;
RWStructuredBuffer<uint> removed_parent_out;
RWStructuredBuffer<uint> match_friend_out;
RWStructuredBuffer<uint> right_leaf_out;
RWStructuredBuffer<uint> left_leaf_out;
RWStructuredBuffer<uint> preorder_link_out;
RWStructuredBuffer<uint> postorder_inverse_link_out;

groupshared uint link_a[16];
groupshared uint link_b[16];
groupshared uint depth_a[16];
groupshared uint depth_b[16];
groupshared uint friend_a[16];
groupshared uint friend_b[16];
groupshared uint flag_a[16];

uint shared_read(uint values[16], uint index, uint fallback)
{
    return index < TEST_COUNT ? values[index] : fallback;
}

void run_compute_depths(uint lane)
{
    link_a[lane] = parent_in[lane];
    depth_a[lane] = pareas_depth_seed();
    GroupMemoryBarrierWithGroupSync();

    uint rounds = pareas_bit_width_u32(TEST_COUNT);
    [loop]
    for (uint round = 0u; round < rounds; round += 1u)
    {
        uint link = link_a[lane];
        uint ancestor_link = shared_read(link_a, link, INVALID);
        uint ancestor_depth = shared_read(depth_a, link, 0u);
        uint next_link;
        uint next_depth;
        pareas_compute_depths_step(
            link,
            depth_a[lane],
            ancestor_link,
            ancestor_depth,
            next_link,
            next_depth);
        link_b[lane] = next_link;
        depth_b[lane] = next_depth;
        GroupMemoryBarrierWithGroupSync();

        link_a[lane] = link_b[lane];
        depth_a[lane] = depth_b[lane];
        GroupMemoryBarrierWithGroupSync();
    }

    depth_out[lane] = pareas_compute_depths_finalize(depth_a[lane]);
}

void run_find_roots(uint lane)
{
    uint initial_link = parent_in[lane];
    link_a[lane] = initial_link;
    GroupMemoryBarrierWithGroupSync();

    uint rounds = pareas_bit_width_u32(TEST_COUNT);
    [loop]
    for (uint round = 0u; round < rounds; round += 1u)
    {
        uint link = link_a[lane];
        uint ancestor_link = shared_read(link_a, link, INVALID);
        link_b[lane] = pareas_find_roots_step(link, ancestor_link);
        GroupMemoryBarrierWithGroupSync();

        link_a[lane] = link_b[lane];
        GroupMemoryBarrierWithGroupSync();
    }

    root_out[lane] = pareas_find_roots_finalize(lane, initial_link, link_a[lane]);
}

void run_remove_nodes(uint lane)
{
    link_a[lane] = parent_in[lane];
    GroupMemoryBarrierWithGroupSync();

    uint rounds = pareas_bit_width_u32(TEST_COUNT);
    [loop]
    for (uint round = 0u; round < rounds; round += 1u)
    {
        uint link = link_a[lane];
        bool link_marked = link < TEST_COUNT && remove_mark_in[link] != 0u;
        uint ancestor_link = shared_read(link_a, link, INVALID);
        link_b[lane] = pareas_find_unmarked_parents_step(
            link,
            link_marked,
            ancestor_link);
        GroupMemoryBarrierWithGroupSync();

        link_a[lane] = link_b[lane];
        GroupMemoryBarrierWithGroupSync();
    }

    unmarked_parent_out[lane] = link_a[lane];
    removed_parent_out[lane] = pareas_remove_nodes_finalize(
        lane,
        remove_mark_in[lane] != 0u,
        link_a[lane]);
}

void run_match_lists(uint lane)
{
    link_a[lane] = list_link_in[lane];
    friend_a[lane] = friend_seed_in[lane];
    GroupMemoryBarrierWithGroupSync();

    uint rounds = pareas_bit_width_u32(TEST_COUNT);
    [loop]
    for (uint round = 0u; round < rounds; round += 1u)
    {
        friend_b[lane] = friend_a[lane];
        link_b[lane] = pareas_match_lists_next_link(
            link_a[lane],
            shared_read(link_a, link_a[lane], INVALID));
        GroupMemoryBarrierWithGroupSync();

        uint friend = friend_a[lane];
        uint scatter_index = pareas_match_lists_scatter_index(friend, link_a[lane]);
        uint scatter_value = pareas_match_lists_scatter_value(
            friend,
            shared_read(link_a, friend, INVALID));
        if (pareas_scatter_link_active(scatter_index) && scatter_index < TEST_COUNT)
            friend_b[scatter_index] = scatter_value;
        GroupMemoryBarrierWithGroupSync();

        friend_a[lane] = friend_b[lane];
        link_a[lane] = link_b[lane];
        GroupMemoryBarrierWithGroupSync();
    }

    match_friend_out[lane] = friend_a[lane];
}

void run_leaf_vectors(uint lane)
{
    flag_a[lane] = 1u;
    GroupMemoryBarrierWithGroupSync();

    uint prev = prev_sibling_in[lane];
    if (pareas_scatter_link_active(prev) && prev < TEST_COUNT)
        flag_a[prev] = 0u;
    link_a[lane] = INVALID;
    GroupMemoryBarrierWithGroupSync();

    uint last_parent = pareas_reorder_leaf_candidate_parent(
        parent_in[lane],
        flag_a[lane] != 0u);
    if (pareas_scatter_link_active(last_parent) && last_parent < TEST_COUNT)
        link_a[last_parent] = lane;
    GroupMemoryBarrierWithGroupSync();

    uint initial_right_link = link_a[lane];
    uint rounds = pareas_bit_width_u32(TEST_COUNT);
    [loop]
    for (uint round = 0u; round < rounds; round += 1u)
    {
        uint link = link_a[lane];
        uint ancestor_link = shared_read(link_a, link, INVALID);
        link_b[lane] = pareas_find_roots_step(link, ancestor_link);
        GroupMemoryBarrierWithGroupSync();

        link_a[lane] = link_b[lane];
        GroupMemoryBarrierWithGroupSync();
    }

    uint right_leaf = pareas_find_roots_finalize(
        lane,
        initial_right_link,
        link_a[lane]);
    right_leaf_out[lane] = right_leaf;
    depth_a[lane] = right_leaf;
    GroupMemoryBarrierWithGroupSync();

    bool first_child = pareas_reorder_is_first_child(prev_sibling_in[lane]);
    link_a[lane] = INVALID;
    GroupMemoryBarrierWithGroupSync();

    uint first_parent = pareas_reorder_leaf_candidate_parent(
        parent_in[lane],
        first_child);
    if (pareas_scatter_link_active(first_parent) && first_parent < TEST_COUNT)
        link_a[first_parent] = lane;
    GroupMemoryBarrierWithGroupSync();

    uint initial_left_link = link_a[lane];
    [loop]
    for (uint round = 0u; round < rounds; round += 1u)
    {
        uint link = link_a[lane];
        uint ancestor_link = shared_read(link_a, link, INVALID);
        link_b[lane] = pareas_find_roots_step(link, ancestor_link);
        GroupMemoryBarrierWithGroupSync();

        link_a[lane] = link_b[lane];
        GroupMemoryBarrierWithGroupSync();
    }

    uint left_leaf = pareas_find_roots_finalize(
        lane,
        initial_left_link,
        link_a[lane]);
    left_leaf_out[lane] = left_leaf;
    depth_b[lane] = left_leaf;
    GroupMemoryBarrierWithGroupSync();

    uint prev_sibling = prev_sibling_in[lane];
    uint prev_right_leaf = shared_read(depth_a, prev_sibling, INVALID);
    preorder_link_out[lane] = pareas_preorder_ordering_link(
        parent_in[lane],
        prev_sibling,
        prev_right_leaf);

    uint next_sibling = next_sibling_in[lane];
    uint next_left_leaf = shared_read(depth_b, next_sibling, INVALID);
    postorder_inverse_link_out[lane] = pareas_postorder_inverse_link(
        parent_in[lane],
        next_sibling,
        next_left_leaf);
}

[shader("compute")]
[numthreads(16, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    if (dtid.x >= TEST_COUNT)
        return;

    run_compute_depths(lane);
    run_find_roots(lane);
    run_remove_nodes(lane);
    run_match_lists(lane);
    run_leaf_vectors(lane);
}
