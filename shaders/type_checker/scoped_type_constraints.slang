import type_checker.concrete_type_equality;
// Infer otherwise free declaration parameters by matching complete checked
// types. Accepted argument bindings take precedence. Inferred references are
// already in caller scope, and repeated parameters must agree structurally.
import type_checker.scoped_type_equality;
import type_checker.constant_constraints;
import type_checker.type_constraint_structure;

public bool scoped_type_and_constant_constraints<Graph : IScopedTypeGraph>(
    uint pattern_tag, uint pattern_payload, uint environment,
    uint actual_tag, uint actual_payload, uint capacity, uint tokens,
    out uint2 inferred[32], out uint inferred_mask,
    out InferredConstant constants[32], out uint constant_mask, bool infer_constants,
    bool allow_root_array_to_slice = false)
{
    static const uint INVALID = 0xffffffffu;
    static const uint LIMIT = 64u;
    uint4 pairs[LIMIT]; uint next[LIMIT]; uint counts[LIMIT];
    inferred_mask = 0u;
    constant_mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++) inferred[slot] = uint2(0u, INVALID);
    for (uint slot = 0u; slot < 32u; slot++) constants[slot] = inferred_constant_reference(uint2(0u, INVALID));
    uint depth = 0u;
    pairs[0u] = uint4(pattern_tag, pattern_payload, actual_tag, actual_payload);
    next[0u] = INVALID;
    for (;;)
    {
        uint4 pair = pairs[depth];
        if (next[depth] == INVALID)
        {
            next[depth] = 0u; counts[depth] = 0u;
            if (application_argument_is_constant(pair.x))
            {
                uint2 pattern; uint2 actual;
                if (!application_constant_argument(pair.x, pair.y, pattern.x, pattern.y) ||
                    !application_constant_argument(pair.z, pair.w, actual.x, actual.y)) return false;
                uint slot = pattern.x == 2u && pattern.y < tokens
                    ? Graph.constant_parameter_slot(pattern.y) : INVALID;
                if (!constant_reference_constraint<Graph>(pattern, slot, environment, actual,
                    tokens, infer_constants, constants, constant_mask)) return false;
            }
            else if (pair.x == 2u)
            {
                uint slot = pair.y < tokens ? Graph.parameter_slot(pair.y) : INVALID;
                if (slot >= 32u || pair.z == 0u || pair.w == INVALID) return false;
                uint2 bound;
                if (!Graph.environment_argument(environment, slot, bound.x, bound.y))
                {
                    uint bit = 1u << slot;
                    if ((inferred_mask & bit) == 0u)
                    {
                        inferred[slot] = pair.zw;
                        inferred_mask |= bit;
                    }
                    bound = inferred[slot];
                }
                if (!scoped_type_refs_equal<Graph>(bound.x, bound.y, INVALID,
                    pair.z, pair.w, INVALID, capacity, tokens)) return false;
            }
            else
            {
                if (pair.x == 0u || pair.x != pair.z || pair.y == INVALID || pair.w == INVALID)
                    return false;
                if (pair.x == 1u)
                {
                    if (pair.y != pair.w) return false;
                }
                else if (pair.x == 3u)
                {
                    ConstraintNodeHeader pattern_header; ConstraintNodeHeader actual_header;
                    if (!constraint_node_header<Graph>(pair.y, capacity, tokens, pattern_header) ||
                        !constraint_node_header<Graph>(pair.w, capacity, tokens, actual_header)) return false;
                    uint kind = pattern_header.kind;
                    uint actual_kind = actual_header.kind;
                    bool slice_coercion = allow_root_array_to_slice && depth == 0u && kind == 3u && actual_kind == 2u;
                    if (kind < 1u || kind > 4u || (kind != actual_kind && !slice_coercion)) return false;
                    if (kind == 1u)
                    {
                        if (!constraint_nominal_headers_equal(pattern_header, actual_header)) return false;
                        counts[depth] = pattern_header.arity;
                    }
                    else
                    {
                        if (kind == 2u)
                        {
                            uint2 length = constraint_array_length<Graph>(pair.y);
                            if (!array_count_reference_constraint<Graph>(length, environment,
                                constraint_array_length<Graph>(pair.w), tokens,
                                infer_constants, constants, constant_mask)) return false;
                        }
                        counts[depth] = 1u;
                    }
                }
                else return false;
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return true;
            depth--; continue;
        }
        uint slot = next[depth]++;
        uint2 left; uint2 right;
        if (!constraint_node_child<Graph>(pair.y, Graph.metadata(pair.y, 0u), slot, left) ||
            !constraint_node_child<Graph>(pair.w, Graph.metadata(pair.w, 0u), slot, right)) return false;
        if (depth + 1u == LIMIT) return false;
        depth++;
        pairs[depth] = uint4(left, right);
        next[depth] = INVALID;
    }
}

public bool scoped_type_ref_constraints<Graph : IScopedTypeGraph>(
    uint pattern_tag, uint pattern_payload, uint environment,
    uint actual_tag, uint actual_payload, uint capacity, uint tokens,
    out uint2 inferred[32], out uint inferred_mask, bool allow_root_array_to_slice = false)
{
    InferredConstant constants[32]; uint constant_mask;
    return scoped_type_and_constant_constraints<Graph>(pattern_tag, pattern_payload, environment,
        actual_tag, actual_payload, capacity, tokens, inferred, inferred_mask,
        constants, constant_mask, false, allow_root_array_to_slice);
}
