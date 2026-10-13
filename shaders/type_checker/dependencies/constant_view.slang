import constant_value;
import type_checker.concrete_type_equality;
// Read-only view of portable constant recipes under an exact caller environment.
// Virtual references exist only during inspection. They are never source rows,
// serialized references, or values that may be published into checked graphs.
import dependency_interface;
import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import type_checker.scoped_type_equality;

public StructuredBuffer<uint2> dependency_constant_ref_by_type;

public bool canonical_constant_view_ranges(out uint parameters, out uint projections,
    out uint parameter_limit)
{
    parameter_limit = 0u;
    uint stride; uint slots;
    type_const_param_scalar_by_token.GetDimensions(parameters, stride);
    type_const_param_slot_by_token.GetDimensions(slots, stride);
    checked_constant_projections.GetDimensions(projections, stride);
    uint types = dependency_type_count();
    // The two source tables address the same declaration-token namespace.
    // Their bounds separate namespaces; validity still requires owned metadata.
    if (parameters != slots || types > 0xffffffffu - parameters ||
        types > 0xffffffffu - projections) return false;
    parameter_limit = parameters + types;
    return true;
}

public bool canonical_constant_view_reference<Graph : IScopedTypeGraph>(uint type,
    out uint2 reference)
{
    reference = uint2(0u, 0xffffffffu);
    if (type >= dependency_type_count()) return false;
    uint kind = dependency_type_word(type * 9u);
    uint parameter_base; uint projection_base; uint limit;
    if (!canonical_constant_view_ranges(parameter_base, projection_base, limit)) return false;
    if (kind == 8u)
    {
        if (!constant_scalar_is_supported(dependency_const_parameter_scalar(type)) ||
            dependency_generic_const_slot(type) >= 32u) return false;
        reference = uint2(2u, parameter_base + type);
        return true;
    }
    if (kind == 9u)
    {
        uint size; uint stride;
        dependency_constant_ref_by_type.GetDimensions(size, stride);
        uint3 portable_value; uint3 source_value;
        if (type >= size || !dependency_literal_constant_value(type, portable_value)) return false;
        uint2 mapped = dependency_constant_ref_by_type[type];
        if (mapped.x != 1u || !Graph.constant_value(mapped.y, source_value) ||
            !constant_values_equal(portable_value, source_value)) return false;
        reference = mapped;
        return true;
    }
    uint target; uint child;
    if (kind != 10u || !dependency_count_projection_child(type, target, child)) return false;
    reference = uint2(3u, projection_base + type);
    return true;
}

public struct CanonicalConstantGraph<Graph : IScopedTypeGraph> : IConstantIdentityGraph
{
    static bool constant_value(uint row, out uint3 value)
    { return Graph.constant_value(row, value); }

    static uint constant_parameter_scalar(uint reference)
    {
        uint parameters; uint projections; uint limit;
        if (!canonical_constant_view_ranges(parameters, projections, limit)) return 0u;
        if (reference < parameters)
            return Graph.parameter_is_valid(reference, true) ? Graph.constant_parameter_scalar(reference) : 0u;
        if (reference >= limit) return 0u;
        uint type = reference - parameters;
        return dependency_generic_const_slot(type) < 32u ? dependency_const_parameter_scalar(type) : 0u;
    }

    static bool constant_projection(uint row, out uint target, out uint2 child)
    {
        target = 0u; child = uint2(0u, 0xffffffffu);
        uint parameters; uint projections; uint limit;
        if (!canonical_constant_view_ranges(parameters, projections, limit)) return false;
        if (row < projections)
        {
            if (!Graph.constant_projection(row, target, child)) return false;
            // An edge stored by a source producer cannot enter the portable
            // overlay just because its payload lies in a virtual address range.
            if (child.x == 1u) { uint3 value; return Graph.constant_value(child.y, value); }
            if (child.x == 2u) return child.y < parameters && Graph.parameter_is_valid(child.y, true);
            return child.x == 3u && child.y < projections;
        }
        uint type = row - projections;
        uint portable_child;
        return type < dependency_type_count() &&
            dependency_count_projection_child(type, target, portable_child) &&
            canonical_constant_view_reference<Graph>(portable_child, child);
    }
}

public struct CanonicalConstantEnvironment<Graph : IScopedTypeGraph> : IConstantReferenceEnvironment
{
    static bool parameter_is_valid(uint reference)
    { return constant_scalar_is_supported(CanonicalConstantGraph<Graph>.constant_parameter_scalar(reference)); }

    static bool substitute(uint environment, uint reference, out uint kind, out uint payload)
    {
        kind = 0u; payload = 0xffffffffu;
        uint parameters; uint projections; uint limit;
        if (!canonical_constant_view_ranges(parameters, projections, limit)) return false;
        if (reference < parameters)
        {
            if (!Graph.parameter_is_valid(reference, true) ||
                !Graph.substitute_constant_parameter(environment, reference, kind, payload)) return false;
            return (kind != 2u || payload < parameters) && (kind != 3u || payload < projections) &&
                constant_scalar_is_supported(constant_reference_scalar<Graph>(uint2(kind, payload)));
        }
        if (reference >= limit || environment == 0xffffffffu) return false;
        uint type = reference - parameters;
        uint scalar = dependency_const_parameter_scalar(type);
        uint slot = dependency_generic_const_slot(type);
        if (!constant_scalar_is_supported(scalar) || slot >= 32u ||
            !Graph.environment_constant(environment, slot, kind, payload)) return false;
        // Only caller-owned source references leave the imported environment.
        return (kind != 2u || payload < parameters) && (kind != 3u || payload < projections) &&
            constant_reference_scalar<Graph>(uint2(kind, payload)) == scalar;
    }
}

public bool canonical_constant_descriptor<Graph : IScopedTypeGraph>(uint environment,
    uint type, out ConstantReferenceDescriptor descriptor, out uint view_tokens)
{
    descriptor = (ConstantReferenceDescriptor)0; view_tokens = 0u;
    uint parameters; uint projections; uint2 reference;
    if (!canonical_constant_view_ranges(parameters, projections, view_tokens) ||
        !canonical_constant_view_reference<Graph>(type, reference) ||
        !inspect_constant_reference<CanonicalConstantGraph<Graph>, CanonicalConstantEnvironment<Graph>>(
            uint3(reference, environment), view_tokens, descriptor)) return false;
    // Unbound imported members cannot masquerade as source declaration tokens.
    return descriptor.disposition != CONSTANT_REFERENCE_SYMBOLIC ||
        descriptor.terminal.y < parameters;
}

public bool canonical_constant_matches<Graph : IScopedTypeGraph>(uint environment,
    uint type, uint2 actual, uint tokens, bool count_identity)
{
    ConstantReferenceDescriptor expected; ConstantReferenceDescriptor candidate;
    uint view_tokens;
    if (!canonical_constant_descriptor<Graph>(environment, type, expected, view_tokens) ||
        !inspect_constant_reference<Graph, ScopedConstantEnvironment<Graph>>(
            uint3(actual, 0xffffffffu), tokens, candidate)) return false;
    return constant_reference_descriptors_equal<CanonicalConstantGraph<Graph>,
        CanonicalConstantEnvironment<Graph>, Graph, ScopedConstantEnvironment<Graph>>(
            expected, candidate, max(view_tokens, tokens), count_identity);
}

public bool canonical_constant_hash<Graph : IScopedTypeGraph>(uint environment,
    uint type, bool count_identity, out uint hash)
{
    hash = 0u;
    ConstantReferenceDescriptor descriptor; uint view_tokens;
    return canonical_constant_descriptor<Graph>(environment, type, descriptor, view_tokens) &&
        constant_reference_descriptor_hash<CanonicalConstantGraph<Graph>,
            CanonicalConstantEnvironment<Graph>>(descriptor, view_tokens, count_identity, hash);
}

// This boundary may return only published source-owned rows or exact source
// parameter declarations. Open imported projections remain canonical recipes.
public bool canonical_constant_source_reference<Graph : IScopedTypeGraph>(uint environment,
    uint type, uint tokens, out uint2 reference)
{
    reference = uint2(0u, 0xffffffffu);
    if (type >= dependency_type_count()) return false;
    uint kind = dependency_type_word(type * 9u);
    uint2 candidate;
    if (kind == 8u)
    {
        uint scalar = dependency_const_parameter_scalar(type);
        uint slot = dependency_generic_const_slot(type);
        // Preserve environment writes to the output even when validation fails.
        if (environment == 0xffffffffu || slot >= 32u ||
            !Graph.environment_constant(environment, slot, reference.x, reference.y) ||
            constant_reference_scalar<Graph>(reference) != scalar) return false;
        candidate = reference;
    }
    else
    {
        uint size; uint stride;
        dependency_constant_ref_by_type.GetDimensions(size, stride);
        if ((kind != 9u && kind != 10u) || type >= size) return false;
        candidate = dependency_constant_ref_by_type[type];
        if ((kind == 9u && candidate.x != 1u) || (kind == 10u && candidate.x != 3u)) return false;
    }
    if (!canonical_constant_matches<Graph>(environment, type, candidate, tokens, false)) return false;
    reference = candidate;
    return true;
}
