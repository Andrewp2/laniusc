// Slang translations of the bulk tree/list primitives from Pareas:
// - src/compiler/passes/util.fut
// - src/compiler/passes/reorder.fut
//
// These helpers are value-level building blocks for shader passes that operate
// on whole parent/link arrays. The calling pass owns the ping-pong buffers,
// scatter stores, and iteration count, matching Futhark's map/iterate/scatter
// structure without hiding a CPU-style tree walk inside a helper.

public static const uint PAREAS_INVALID = 0xffffffffu;

public bool pareas_valid_link(uint link)
{
    return link != PAREAS_INVALID;
}

public uint pareas_bit_width_u32(uint value)
{
    uint width = 0u;
    [loop]
    for (uint v = value; v != 0u && width < 32u; v >>= 1u)
        width += 1u;
    return width;
}

public uint pareas_depth_seed()
{
    return 1u;
}

public void pareas_compute_depths_step(
    uint link,
    uint depth,
    uint ancestor_link,
    uint ancestor_depth,
    out uint next_link,
    out uint next_depth)
{
    uint inherited_depth = pareas_valid_link(link) ? ancestor_depth : 0u;
    next_depth = max(depth + inherited_depth, depth);
    next_link = pareas_valid_link(link) ? ancestor_link : link;
}

public uint pareas_compute_depths_finalize(uint depth)
{
    return depth > 0u ? depth - 1u : 0u;
}

public uint pareas_find_roots_step(uint link, uint ancestor_link)
{
    return (!pareas_valid_link(link) || !pareas_valid_link(ancestor_link))
        ? link
        : ancestor_link;
}

public uint pareas_find_roots_finalize(uint node, uint initial_link, uint resolved_link)
{
    return !pareas_valid_link(initial_link) ? node : resolved_link;
}

public uint pareas_find_unmarked_parents_step(
    uint link,
    bool link_marked,
    uint ancestor_link)
{
    return (!pareas_valid_link(link) || !link_marked) ? link : ancestor_link;
}

public uint pareas_remove_nodes_finalize(uint node, bool remove, uint resolved_parent)
{
    return remove ? node : resolved_parent;
}

public bool pareas_scatter_link_active(uint link)
{
    return pareas_valid_link(link);
}

public uint pareas_invert_scatter_index(uint link)
{
    return link;
}

public uint pareas_invert_scatter_value(uint node)
{
    return node;
}

public uint pareas_match_lists_scatter_index(uint friend, uint link)
{
    return pareas_valid_link(friend) ? link : PAREAS_INVALID;
}

public uint pareas_match_lists_scatter_value(uint friend, uint friend_link)
{
    return pareas_valid_link(friend) ? friend_link : PAREAS_INVALID;
}

public uint pareas_match_lists_next_link(uint link, uint ancestor_link)
{
    return pareas_valid_link(link) ? ancestor_link : link;
}

public void pareas_linked_prefix_count_step(
    uint link,
    uint count,
    uint ancestor_link,
    uint ancestor_count,
    out uint next_link,
    out uint next_count)
{
    next_count = count + (pareas_valid_link(link) ? ancestor_count : 0u);
    next_link = pareas_valid_link(link) ? ancestor_link : link;
}

public bool pareas_reorder_is_first_child(uint prev_sibling)
{
    return !pareas_valid_link(prev_sibling);
}

public uint pareas_reorder_leaf_candidate_parent(uint parent, bool keep_child)
{
    return keep_child ? parent : PAREAS_INVALID;
}

public uint pareas_preorder_ordering_link(
    uint parent,
    uint prev_sibling,
    uint prev_sibling_right_leaf)
{
    return !pareas_valid_link(prev_sibling) ? parent : prev_sibling_right_leaf;
}

public uint pareas_postorder_inverse_link(
    uint parent,
    uint next_sibling,
    uint next_sibling_left_leaf)
{
    return !pareas_valid_link(next_sibling) ? parent : next_sibling_left_leaf;
}

public uint pareas_reordered_parent(uint old_parent, uint old_parent_new_index)
{
    return pareas_valid_link(old_parent) ? old_parent_new_index : PAREAS_INVALID;
}
