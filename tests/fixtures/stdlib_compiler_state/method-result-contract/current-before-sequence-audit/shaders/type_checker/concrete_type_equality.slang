// Compare checked type references without collapsing compounds to a scalar
// code or treating equal machine widths as equal types. Declaration fields
// are not traversed: nominal identity and every type argument define a named
// type. A bounded stack makes malformed or cyclic instance graphs fail closed.
// Structural traversal does not require declaration identity or layout widths.
// Native closure checks consume this subset of the checked type graph.
public interface ITypeStructureGraph
{
    // Kind (0), arity (2), element tag/payload (3/4), array length kind (5).
    static uint metadata(uint instance, uint field);
    static bool argument(uint instance, uint slot, out uint tag, out uint payload);
}

public interface IConcreteTypeGraph : ITypeStructureGraph
{
    // kind, local declaration, arity, element tag/payload, length kind/payload,
    // external library/unit/declaration identity, in that order.
    // For named nodes field 5 stores the type count and interleaving flag;
    // field 6 is the constant-position mask. Array nodes use fields 5/6
    // for their tagged length reference. Arguments retain source order.
}

#include "application_argument_reference.slang"

public bool concrete_type_refs_equal<Graph : IConcreteTypeGraph>(
    uint left_tag, uint left_payload, uint right_tag, uint right_payload,
    uint token_capacity)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    uint4 pairs[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint counts[DEPTH_LIMIT];
    uint depth = 0u;
    pairs[0u] = uint4(left_tag, left_payload, right_tag, right_payload);
    next[0u] = INVALID;
    for (;;)
    {
        uint4 pair = pairs[depth];
        if (next[depth] == INVALID)
        {
            if (pair.x == 0u || pair.x != pair.z || pair.y == INVALID || pair.w == INVALID)
                return false;
            counts[depth] = 0u;
            next[depth] = 0u;
            if (pair.x != 3u)
            {
                if (pair.y != pair.w) return false;
            }
            else
            {
                if (pair.y >= token_capacity || pair.w >= token_capacity) return false;
                uint kind = Graph.metadata(pair.y, 0u);
                if (kind < 1u || kind > 4u || kind != Graph.metadata(pair.w, 0u)) return false;
                if (kind == 1u)
                {
                    uint left_decl = Graph.metadata(pair.y, 1u);
                    uint right_decl = Graph.metadata(pair.w, 1u);
                    if (left_decl != INVALID || right_decl != INVALID)
                    {
                        if (left_decl >= token_capacity || left_decl != right_decl) return false;
                    }
                    else
                    {
                        for (uint field = 7u; field <= 9u; field++)
                        {
                            uint identity = Graph.metadata(pair.y, field);
                            if (identity == INVALID || identity != Graph.metadata(pair.w, field)) return false;
                        }
                    }
                    counts[depth] = Graph.metadata(pair.y, 2u);
                    if (counts[depth] > token_capacity ||
                        counts[depth] != Graph.metadata(pair.w, 2u)) return false;
                }
                else
                {
                    if (kind == 2u && (Graph.metadata(pair.y, 5u) != Graph.metadata(pair.w, 5u) ||
                        Graph.metadata(pair.y, 6u) != Graph.metadata(pair.w, 6u))) return false;
                    counts[depth] = 1u;
                }
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return true;
            depth--;
            continue;
        }
        uint slot = next[depth]++;
        uint tag_l; uint payload_l; uint tag_r; uint payload_r;
        if (Graph.metadata(pair.y, 0u) == 1u)
        {
            if (!Graph.argument(pair.y, slot, tag_l, payload_l) ||
                !Graph.argument(pair.w, slot, tag_r, payload_r)) return false;
        }
        else
        {
            tag_l = Graph.metadata(pair.y, 3u); payload_l = Graph.metadata(pair.y, 4u);
            tag_r = Graph.metadata(pair.w, 3u); payload_r = Graph.metadata(pair.w, 4u);
        }
        if (depth + 1u == DEPTH_LIMIT) return false;
        depth++;
        pairs[depth] = uint4(tag_l, payload_l, tag_r, payload_r);
        next[depth] = INVALID;
    }
}
