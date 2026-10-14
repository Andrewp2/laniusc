// Compare a declaration-side type under its enclosing concrete environment.
// The environment applies to symbolic leaves only. Once a leaf is replaced by
// an argument, that argument is already checked in the caller's scope.
import type_checker.concrete_type_equality;

// A parameter reference carries its declaration identity, including domain.
// The adapter must validate that identity before looking up an environment
// binding. Packed graphs can use complete owned keys without exposing slots.
public interface IParameterScopedTypeGraph : ITypeIdentityGraph
{
    static bool parameter_is_valid(uint reference, bool constant);
    static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload);
    static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value);
}

// Source inference also needs nominal domain summaries, declaration slots,
// and its existing environment policies. Retain the complete application
// capability here without requiring it of owned-parameter comparison graphs.
public interface IScopedTypeGraph : IParameterScopedTypeGraph, IConcreteTypeGraph
{
    static uint parameter_slot(uint parameter_token);
    static uint constant_parameter_slot(uint parameter_token);
    static bool environment_constant(uint environment, uint slot, out uint kind, out uint value);
    static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload);
}

// Source adapters preserve existing slot-based environment lookup; this bridge
// does not add owner checks. Packed adapters must validate the original owned
// parameter against the environment before selecting its binding.
public bool source_parameter_is_valid<Graph : IScopedTypeGraph>(uint reference, bool constant)
{
    return constant ? Graph.constant_parameter_slot(reference) < 32u :
        Graph.parameter_slot(reference) != 0xffffffffu;
}

public bool source_substitute_type_parameter<Graph : IScopedTypeGraph>(
    uint environment, uint reference, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    uint slot = Graph.parameter_slot(reference);
    return slot != 0xffffffffu && Graph.environment_argument(environment, slot, tag, payload);
}

public bool source_substitute_constant_parameter<Graph : IScopedTypeGraph>(
    uint environment, uint reference, out uint kind, out uint value)
{
    kind = 0u; value = 0xffffffffu;
    uint slot = Graph.constant_parameter_slot(reference);
    return slot < 32u && Graph.environment_constant(environment, slot, kind, value);
}

// Constant substitution is owned by the scoped graph. A replacement already
// belongs to the caller; its original parameter slot is never reapplied.
public struct ScopedConstantEnvironment<Graph : IParameterScopedTypeGraph> : IConstantReferenceEnvironment
{
    [ForceInline]
    static bool parameter_is_valid(uint reference)
    { return Graph.parameter_is_valid(reference, true); }
    [ForceInline]
    static bool substitute(uint environment, uint reference, out uint kind, out uint payload)
    { return Graph.substitute_constant_parameter(environment, reference, kind, payload); }
}

public bool scoped_constant_reference<Graph : IParameterScopedTypeGraph>(
    inout uint3 reference, uint tokens, out ConstantReferenceDescriptor descriptor)
{
    if (!inspect_constant_reference<Graph, ScopedConstantEnvironment<Graph>>(reference, tokens, descriptor))
        return false;
    reference = descriptor.root;
    return true;
}

// Typed identity (count_identity false) or count identity (true). The walker
// below calls this once per visited node so it is expanded at one site only.
public bool scoped_constant_refs_or_counts_equal<
    LeftGraph : IParameterScopedTypeGraph, RightGraph : IParameterScopedTypeGraph>(
    uint3 left, uint3 right, uint tokens, bool count_identity)
{
    ConstantReferenceDescriptor a; ConstantReferenceDescriptor b;
    return scoped_constant_reference<LeftGraph>(left, tokens, a) &&
        scoped_constant_reference<RightGraph>(right, tokens, b) &&
        constant_reference_descriptors_equal<LeftGraph, ScopedConstantEnvironment<LeftGraph>,
            RightGraph, ScopedConstantEnvironment<RightGraph>>(a, b, tokens, count_identity);
}

[ForceInline]
public bool scoped_constant_refs_equal<
    LeftGraph : IParameterScopedTypeGraph, RightGraph : IParameterScopedTypeGraph>(
    uint3 left, uint3 right, uint tokens)
{
    return scoped_constant_refs_or_counts_equal<LeftGraph, RightGraph>(left, right, tokens, false);
}

[ForceInline]
public bool scoped_constant_counts_equal<
    LeftGraph : IParameterScopedTypeGraph, RightGraph : IParameterScopedTypeGraph>(
    uint3 left, uint3 right, uint tokens)
{
    return scoped_constant_refs_or_counts_equal<LeftGraph, RightGraph>(left, right, tokens, true);
}

public bool scoped_constant_ref_hash<Graph : IParameterScopedTypeGraph>(
    uint3 reference, uint tokens, out uint result)
{
    result = 0u;
    ConstantReferenceDescriptor descriptor;
    return scoped_constant_reference<Graph>(reference, tokens, descriptor) &&
        constant_reference_descriptor_hash<Graph, ScopedConstantEnvironment<Graph>>(
            descriptor, tokens, false, result);
}

public bool scoped_constant_count_hash<Graph : IParameterScopedTypeGraph>(
    uint3 reference, uint tokens, out uint result)
{
    result = 0u;
    ConstantReferenceDescriptor descriptor;
    return scoped_constant_reference<Graph>(reference, tokens, descriptor) &&
        constant_reference_descriptor_hash<Graph, ScopedConstantEnvironment<Graph>>(
            descriptor, tokens, true, result);
}

public bool scoped_type_refs_equal_graphs<
    LeftGraph : IParameterScopedTypeGraph, RightGraph : IParameterScopedTypeGraph>(
    uint left_tag, uint left_payload, uint left_context,
    uint right_tag, uint right_payload, uint right_context,
    uint left_type_capacity, uint right_type_capacity, uint token_capacity)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    uint4 pairs[DEPTH_LIMIT];
    uint2 contexts[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint counts[DEPTH_LIMIT];
    uint depth = 0u;
    pairs[0u] = uint4(left_tag, left_payload, right_tag, right_payload);
    contexts[0u] = uint2(left_context, right_context);
    next[0u] = INVALID;
    for (;;)
    {
        uint4 pair = pairs[depth];
        uint2 context = contexts[depth];
        if (next[depth] == INVALID)
        {
            if (pair.x == 2u && context.x != INVALID)
            {
                if (pair.y >= token_capacity ||
                    !LeftGraph.substitute_type_parameter(context.x, pair.y, pair.x, pair.y) ||
                    (pair.x != 1u && pair.x != 2u && pair.x != 3u)) return false;
                context.x = INVALID;
            }
            if (pair.z == 2u && context.y != INVALID)
            {
                if (pair.w >= token_capacity ||
                    !RightGraph.substitute_type_parameter(context.y, pair.w, pair.z, pair.w) ||
                    (pair.z != 1u && pair.z != 2u && pair.z != 3u)) return false;
                context.y = INVALID;
            }
            pairs[depth] = pair;
            contexts[depth] = context;
            counts[depth] = 0u;
            next[depth] = 0u;
            // A constant argument (typed identity) or an array length (count
            // identity) is compared once, after classification, by one call.
            bool compare_constant = false; bool count_identity = false;
            uint2 constant_left = uint2(0u, INVALID); uint2 constant_right = uint2(0u, INVALID);
            if (application_argument_is_constant(pair.x) || application_argument_is_constant(pair.z))
            {
                if (!application_constant_argument(pair.x, pair.y, constant_left.x, constant_left.y) ||
                    !application_constant_argument(pair.z, pair.w, constant_right.x, constant_right.y))
                    return false;
                compare_constant = true;
            }
            else if (pair.x == 0u || pair.x != pair.z || pair.y == INVALID || pair.w == INVALID)
                return false;
            else if (pair.x != 3u)
            {
                if (pair.x != 1u && pair.x != 2u && !application_argument_is_constant(pair.x)) return false;
                if (pair.y != pair.w) return false;
                if (pair.x == 2u && (pair.y >= token_capacity ||
                    (!LeftGraph.parameter_is_valid(pair.y, false) ||
                        !RightGraph.parameter_is_valid(pair.w, false)))) return false;
            }
            else
            {
                if (pair.y >= left_type_capacity || pair.w >= right_type_capacity) return false;
                uint kind = LeftGraph.metadata(pair.y, 0u);
                if (kind < 1u || kind > 4u || kind != RightGraph.metadata(pair.w, 0u)) return false;
                if (kind == 1u)
                {
                    uint left_decl = LeftGraph.metadata(pair.y, 1u);
                    uint right_decl = RightGraph.metadata(pair.w, 1u);
                    if (left_decl != INVALID || right_decl != INVALID)
                    {
                        if (left_decl >= token_capacity || left_decl != right_decl) return false;
                    }
                    else
                    {
                        for (uint field = 7u; field <= 9u; field++)
                        {
                            uint identity = LeftGraph.metadata(pair.y, field);
                            if (identity == INVALID || identity != RightGraph.metadata(pair.w, field)) return false;
                        }
                    }
                    counts[depth] = LeftGraph.metadata(pair.y, 2u);
                    if (counts[depth] > NOMINAL_APPLICATION_ARGUMENT_LIMIT ||
                        counts[depth] != RightGraph.metadata(pair.w, 2u)) return false;
                }
                else
                {
                    if (kind == 2u)
                    {
                        constant_left = uint2(LeftGraph.metadata(pair.y, 5u), LeftGraph.metadata(pair.y, 6u));
                        constant_right = uint2(RightGraph.metadata(pair.w, 5u), RightGraph.metadata(pair.w, 6u));
                        compare_constant = true; count_identity = true;
                    }
                    counts[depth] = 1u;
                }
            }
            if (compare_constant && !scoped_constant_refs_or_counts_equal<LeftGraph, RightGraph>(
                uint3(constant_left, context.x), uint3(constant_right, context.y), token_capacity,
                count_identity)) return false;
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return true;
            depth--;
            continue;
        }
        uint slot = next[depth]++;
        uint tag_l; uint payload_l; uint tag_r; uint payload_r;
        if (LeftGraph.metadata(pair.y, 0u) == 1u)
        {
            if (!LeftGraph.argument(pair.y, slot, tag_l, payload_l) ||
                !RightGraph.argument(pair.w, slot, tag_r, payload_r)) return false;
        }
        else
        {
            tag_l = LeftGraph.metadata(pair.y, 3u); payload_l = LeftGraph.metadata(pair.y, 4u);
            tag_r = RightGraph.metadata(pair.w, 3u); payload_r = RightGraph.metadata(pair.w, 4u);
        }
        if (depth + 1u == DEPTH_LIMIT) return false;
        depth++;
        pairs[depth] = uint4(tag_l, payload_l, tag_r, payload_r);
        contexts[depth] = context;
        next[depth] = INVALID;
    }
}

// Existing source comparisons use one graph namespace. The shared walker above
// also compares input and normalized solver stores without fabricating node IDs.
public bool scoped_type_refs_equal<Graph : IParameterScopedTypeGraph>(
    uint left_tag, uint left_payload, uint left_context,
    uint right_tag, uint right_payload, uint right_context, uint type_capacity,
    uint token_capacity)
{
    return scoped_type_refs_equal_graphs<Graph, Graph>(
        left_tag, left_payload, left_context, right_tag, right_payload, right_context,
        type_capacity, type_capacity, token_capacity);
}
