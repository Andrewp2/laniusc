// Structural view shared by source constraints and owned implementation
// matching. Array lengths are explicit operands; callers choose whether to
// traverse them or apply their existing constant-binding policy.
import type_checker.concrete_type_equality;

public struct ConstraintNodeHeader
{
    public uint kind;
    public uint arity;
    public uint local_nominal;
    public uint3 external_nominal;
}

public bool constraint_node_header<Graph : ITypeIdentityGraph>(
    uint node, uint node_capacity, uint identity_capacity,
    out ConstraintNodeHeader header)
{
    header = (ConstraintNodeHeader)0;
    header.local_nominal = 0xffffffffu;
    if (node >= node_capacity) return false;
    header.kind = Graph.metadata(node, 0u);
    if (header.kind < 1u || header.kind > 4u) return false;
    header.arity = 1u;
    if (header.kind != 1u) return true;
    header.local_nominal = Graph.metadata(node, 1u);
    if (header.local_nominal != 0xffffffffu)
    {
        if (header.local_nominal >= identity_capacity) return false;
    }
    else
    {
        header.external_nominal = uint3(Graph.metadata(node, 7u),
            Graph.metadata(node, 8u), Graph.metadata(node, 9u));
        if (any(header.external_nominal == uint3(0xffffffffu, 0xffffffffu, 0xffffffffu)))
            return false;
    }
    header.arity = Graph.metadata(node, 2u);
    return header.arity <= 32u;
}

public bool constraint_nominal_headers_equal(
    ConstraintNodeHeader left, ConstraintNodeHeader right)
{
    if (left.kind != 1u || right.kind != 1u || left.arity != right.arity) return false;
    if (left.local_nominal != 0xffffffffu || right.local_nominal != 0xffffffffu)
        return left.local_nominal == right.local_nominal;
    return all(left.external_nominal == right.external_nominal);
}

public bool constraint_node_child<Graph : ITypeIdentityGraph>(
    uint node, uint kind, uint slot, out uint2 child)
{
    child = uint2(0u, 0xffffffffu);
    if (kind == 1u) return Graph.argument(node, slot, child.x, child.y);
    if (kind < 2u || kind > 4u || slot != 0u) return false;
    child = uint2(Graph.metadata(node, 3u), Graph.metadata(node, 4u));
    return true;
}

public uint2 constraint_array_length<Graph : ITypeIdentityGraph>(uint node)
{ return uint2(Graph.metadata(node, 5u), Graph.metadata(node, 6u)); }
