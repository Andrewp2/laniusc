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
// The result of inspecting both references (scoped_constant_reference) and
// comparing their descriptors (constant_reference_descriptors_equal): left
// inspection (phase 0), right inspection (1), then the lockstep identity walk
// (2), with one step call site per graph. Every identity step follows at most
// one substitution, as constant_identity_step does.
public bool scoped_constant_refs_or_counts_equal<
    LeftGraph : IParameterScopedTypeGraph, RightGraph : IParameterScopedTypeGraph>(
    uint3 left, uint3 right, uint tokens, bool count_identity)
{
    ConstantInspection a = constant_inspection_begin(left);
    ConstantInspection b = constant_inspection_begin(right);
    uint phase = 0u; uint walked = 0u;
    uint3 walk_a = left; uint3 walk_b = right; uint3 next_a = left; uint3 next_b = right;
    bool followed_a = false; bool followed_b = false; bool done_a = false; bool done_b = false;
    uint step_a = 0u; uint step_b = 0u; uint scalar_a = 0u; uint scalar_b = 0u;
    // Each inspection takes at most two passes of steps, and each identity
    // step at most two loop iterations.
    [loop]
    for (uint guard = 0u; guard < 8u * CONSTANT_REFERENCE_WORK_LIMIT; guard++)
    {
        if (phase != 1u && !done_a)
        {
            uint3 next; uint scalar; uint3 value;
            uint step = constant_reference_step<LeftGraph, ScopedConstantEnvironment<LeftGraph>>(
                phase == 0u ? a.reference : walk_a, tokens, next, scalar, value);
            if (phase == 0u)
            {
                constant_inspection_feed(a, step, next, scalar, value);
                if (a.result == CONSTANT_INSPECTION_REJECTED) return false;
                if (a.result == CONSTANT_INSPECTION_ACCEPTED) phase = 1u;
                continue;
            }
            if (step == 4u && !followed_a) { walk_a = next; followed_a = true; }
            else { done_a = true; step_a = step; scalar_a = scalar; next_a = next; }
        }
        if (phase != 0u && !done_b)
        {
            uint3 next; uint scalar; uint3 value;
            uint step = constant_reference_step<RightGraph, ScopedConstantEnvironment<RightGraph>>(
                phase == 1u ? b.reference : walk_b, tokens, next, scalar, value);
            if (phase == 1u)
            {
                constant_inspection_feed(b, step, next, scalar, value);
                if (b.result == CONSTANT_INSPECTION_REJECTED) return false;
                if (b.result == CONSTANT_INSPECTION_ACCEPTED)
                {
                    uint prelude = constant_descriptors_equal_prelude(a.descriptor, b.descriptor, count_identity);
                    if (prelude != CONSTANT_IDENTITY_WALK) return prelude == 1u;
                    phase = 2u; walk_a = a.descriptor.root; walk_b = b.descriptor.root;
                }
                continue;
            }
            if (step == 4u && !followed_b) { walk_b = next; followed_b = true; }
            else { done_b = true; step_b = step; scalar_b = scalar; next_b = next; }
        }
        if (!done_a || !done_b) continue;
        if (step_a != step_b || scalar_a != scalar_b) return false;
        if (step_a == 2u) return walk_a.y == walk_b.y;
        if (step_a != 3u) return false;
        walk_a = next_a; walk_b = next_b;
        done_a = false; done_b = false; followed_a = false; followed_b = false;
        walked++;
        if (walked == CONSTANT_REFERENCE_WORK_LIMIT) return false;
    }
    return false;
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
// Inspection (scoped_constant_reference), then the descriptor hash
// (constant_reference_descriptor_hash) whose identity walk shares the one
// step call site.
public bool scoped_constant_ref_or_count_hash<Graph : IParameterScopedTypeGraph>(
    uint3 reference, uint tokens, bool count_identity, out uint result)
{
    result = 0u;
    ConstantInspection inspection = constant_inspection_begin(reference);
    bool walking = false; bool followed = false; uint3 walk = reference;
    uint walked = 0u; uint hash = 0u;
    [loop]
    for (uint guard = 0u; guard < 6u * CONSTANT_REFERENCE_WORK_LIMIT; guard++)
    {
        uint3 next; uint scalar; uint3 value;
        uint step = constant_reference_step<Graph, ScopedConstantEnvironment<Graph>>(
            walking ? walk : inspection.reference, tokens, next, scalar, value);
        if (!walking)
        {
            constant_inspection_feed(inspection, step, next, scalar, value);
            if (inspection.result == CONSTANT_INSPECTION_RUNNING) continue;
            if (inspection.result != CONSTANT_INSPECTION_ACCEPTED) return false;
            uint prelude = constant_descriptor_hash_prelude(inspection.descriptor, count_identity, hash);
            if (prelude != CONSTANT_IDENTITY_WALK)
            {
                if (prelude == 1u) result = hash;
                return prelude == 1u;
            }
            walking = true; walk = inspection.descriptor.root;
            continue;
        }
        // One identity step of constant_reference_descriptor_hash.
        if (step == 4u && !followed) { walk = next; followed = true; continue; }
        followed = false;
        hash = constant_identity_hash_mix(hash, step);
        hash = constant_identity_hash_mix(hash, scalar);
        if (step == 2u)
        {
            result = constant_identity_hash_mix(hash, walk.y);
            return true;
        }
        if (step != 3u) return false;
        walk = next; walked++;
        if (walked == CONSTANT_REFERENCE_WORK_LIMIT) return false;
    }
    return false;
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
