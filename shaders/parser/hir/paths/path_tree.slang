import generated_parse_production_ids;

public static const uint PATH_TREE_INVALID = 0xffffffffu;
public static const uint PATH_TREE_OWNER_MASK = 0x7fffffffu;

public bool is_path_segment(uint prod)
{
    return prod == PROD_TYPE_PATH_IDENT || prod == PROD_PATH_IDENT ||
           prod == PROD_PATH_IDENT_ARGS || prod == PROD_BOUND_TYPE_PATH_IDENT ||
           prod == PROD_ARRAY_LENGTH_PATH_IDENT || prod == PROD_CAST_TYPE_PATH_IDENT;
}

bool is_path_tail(uint prod)
{
    return prod == PROD_TYPE_PATH_MORE || prod == PROD_PATH_MORE ||
           prod == PROD_BOUND_TYPE_PATH_MORE || prod == PROD_ARRAY_LENGTH_PATH_MORE ||
           prod == PROD_CAST_TYPE_PATH_MORE;
}

public uint path_first_segment(
    uint path, uint active, StructuredBuffer<uint> first_child, StructuredBuffer<uint> node_kind)
{
    uint segment = first_child[path];
    return segment < active && segment > path && is_path_segment(node_kind[segment])
        ? segment : PATH_TREE_INVALID;
}

public uint path_next_segment(
    uint segment, uint active, StructuredBuffer<uint> first_child,
    StructuredBuffer<uint> next_sibling, StructuredBuffer<uint> node_kind)
{
    // Raw nodes are in preorder. The tail is a following sibling, and its
    // segment is a child, so each iteration advances to a greater index.
    uint tail = next_sibling[segment];
    if (tail >= active || tail <= segment || !is_path_tail(node_kind[tail]))
        return PATH_TREE_INVALID;
    return path_first_segment(tail, active, first_child, node_kind);
}

public uint path_root_owner(uint encoded)
{
    return (encoded & PATH_TREE_OWNER_MASK) - 1u;
}
