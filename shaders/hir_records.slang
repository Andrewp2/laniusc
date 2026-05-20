public static const uint HIR_RECORD_INVALID = 0xffffffffu;

public static const uint HIR_NODE_ORDINAL_NODE_MASK = 0x0fffffffu;
public static const uint HIR_NODE_ORDINAL_ORDINAL_MASK = 0x0fu;
public static const uint HIR_NODE_ORDINAL_ORDINAL_SHIFT = 28u;

public uint pack_hir_node_ordinal(uint node, uint ordinal)
{
    if (node == HIR_RECORD_INVALID || node > HIR_NODE_ORDINAL_NODE_MASK ||
        ordinal > HIR_NODE_ORDINAL_ORDINAL_MASK)
        return HIR_RECORD_INVALID;
    return node | (ordinal << HIR_NODE_ORDINAL_ORDINAL_SHIFT);
}

public uint hir_node_ordinal_node(uint record)
{
    return record == HIR_RECORD_INVALID ? HIR_RECORD_INVALID : record & HIR_NODE_ORDINAL_NODE_MASK;
}

public uint hir_node_ordinal_ordinal(uint record)
{
    return record == HIR_RECORD_INVALID ? HIR_RECORD_INVALID :
        (record >> HIR_NODE_ORDINAL_ORDINAL_SHIFT) & HIR_NODE_ORDINAL_ORDINAL_MASK;
}
