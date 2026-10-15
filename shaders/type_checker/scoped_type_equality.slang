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

// Typed (count_identity false) or count identity hash. Walkers call this
// once per visited node so it is expanded at one site only.
public bool scoped_constant_ref_or_count_hash<Graph : IParameterScopedTypeGraph>(
    uint3 reference, uint tokens, bool count_identity, out uint result)
{
    result = 0u;
    ConstantReferenceDescriptor descriptor;
    return scoped_constant_reference<Graph>(reference, tokens, descriptor) &&
        constant_reference_descriptor_hash<Graph, ScopedConstantEnvironment<Graph>>(
            descriptor, tokens, count_identity, result);
}

[ForceInline]
public bool scoped_constant_ref_hash<Graph : IParameterScopedTypeGraph>(
    uint3 reference, uint tokens, out uint result)
{
    return scoped_constant_ref_or_count_hash<Graph>(reference, tokens, false, result);
}

[ForceInline]
public bool scoped_constant_count_hash<Graph : IParameterScopedTypeGraph>(
    uint3 reference, uint tokens, out uint result)
{
    return scoped_constant_ref_or_count_hash<Graph>(reference, tokens, true, result);
}

// Local frame storage. The scratch expansion is
// scoped_type_refs_equal_graphs_scratch.
#define SCOPED_TYPE_EQUALITY_WALK scoped_type_refs_equal_graphs
#define SCOPED_TYPE_EQUALITY_FRAMES uint4 pairs[DEPTH_LIMIT]; uint2 contexts[DEPTH_LIMIT]; uint next[DEPTH_LIMIT]; uint counts[DEPTH_LIMIT];
#define SE_PAIR(d) pairs[d]
#define SE_PUSH(d, p, c) pairs[d] = p; contexts[d] = c; next[d] = INVALID
#define SE_CLASSIFIED(d, p, c) pairs[d] = p; contexts[d] = c; counts[d] = 0u; next[d] = 0u
#define SE_CONTEXT(d) contexts[d]
#define SE_NEXT(d) next[d]
#define SE_NEXT_INCREMENT(d) next[d]++
#define SE_COUNT(d) counts[d]
#define SE_SET_COUNT(d, v) counts[d] = v
#include "scoped_type_equality_walk.slang"
#undef SCOPED_TYPE_EQUALITY_WALK
#undef SCOPED_TYPE_EQUALITY_FRAMES
#undef SE_PAIR
#undef SE_PUSH
#undef SE_CLASSIFIED
#undef SE_CONTEXT
#undef SE_NEXT
#undef SE_NEXT_INCREMENT
#undef SE_COUNT
#undef SE_SET_COUNT

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
