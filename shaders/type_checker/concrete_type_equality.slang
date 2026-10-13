import constant_value;
import primitive_types;
// Compare checked type references without collapsing compounds to a scalar
// code or treating equal machine widths as equal types. Declaration fields
// are not traversed: nominal identity and every type argument define a named
// type. A bounded stack makes malformed or cyclic instance graphs fail closed.
// Structural traversal does not require declaration identity or layout widths.
// Native closure checks consume this subset of the checked type graph.
public interface ITypeStructureGraph
{
    // Kind (0), arity (2), element tag/payload (3/4), array length kind/payload (5/6).
    static uint metadata(uint instance, uint field);
    static bool argument(uint instance, uint slot, out uint tag, out uint payload);
}

// Identity comparison extends structure with nominal identity and array
// length payload. It consumes every ordered tagged operand directly; it does
// not need a nominal application's mapping from domain slots to operands.
public interface IConstantIdentityGraph
{
    // Concrete payloads are graph-owned addresses, never the value itself.
    static bool constant_value(uint row, out uint3 value);
    static uint constant_parameter_scalar(uint reference);
    static bool constant_projection(uint row, out uint target_scalar, out uint2 child);
}

public interface ITypeIdentityGraph : ITypeStructureGraph, IConstantIdentityGraph
{
    // Additional metadata: local declaration (1),
    // external library/unit/declaration identity (7/8/9). A local declaration
    // of INVALID selects the external identity. Fields 5/6 describe lengths
    // only for array nodes in this capability; consumers must not request a
    // nominal domain summary without the stronger IConcreteTypeGraph contract.
}

public interface IConcreteTypeGraph : ITypeIdentityGraph
{
    // Source application environments additionally map separate type/constant
    // slots onto the same source-ordered operands. For named nodes field 5
    // stores the type count and interleaving flag; field 6 stores the constant
    // position mask. Array length fields retain the identity-graph meaning.
}

#include "application_argument_reference.slang"
#include "constant_reference_identity.slang"

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
            counts[depth] = 0u;
            next[depth] = 0u;
            if (application_argument_is_constant(pair.x) || application_argument_is_constant(pair.z))
            {
                uint2 left; uint2 right;
                if (!application_constant_argument(pair.x, pair.y, left.x, left.y) ||
                    !application_constant_argument(pair.z, pair.w, right.x, right.y) ||
                    !constant_refs_equal<Graph, Graph>(left, right, token_capacity)) return false;
            }
            else if (pair.x == 0u || pair.x != pair.z || pair.y == INVALID || pair.w == INVALID)
                return false;
            else if (pair.x != 3u)
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
                    if (kind == 2u && !constant_refs_equal<Graph, Graph>(
                        uint2(Graph.metadata(pair.y, 5u), Graph.metadata(pair.y, 6u)),
                        uint2(Graph.metadata(pair.w, 5u), Graph.metadata(pair.w, 6u)),
                        token_capacity, true)) return false;
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
