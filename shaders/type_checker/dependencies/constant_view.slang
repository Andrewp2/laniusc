import constant_value;
import type_checker.concrete_type_equality;
// Read-only view of portable constant recipes under an exact caller environment.
// Virtual references exist only during inspection. They are never source rows,
// serialized references, or values that may be published into checked graphs.
import dependency_interface;
import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import type_checker.scoped_type_equality;
import type_checker.canonical.canonical_api;

public StructuredBuffer<uint2> dependency_constant_ref_by_type;

// The job-wide canonical ID of a constant node of the resident page
// (canonical_dependency.slang), or CT_UNKNOWN.
uint canonical_constant_id(uint type)
{
    uint base = dependency_constant_type_span_base();
    uint capacity = ct_dependency_capacity();
    if (type >= dependency_type_count() || base > capacity || type >= capacity - base) return CT_UNKNOWN;
    return canonical_dependency_type[base + type];
}

// Bounds of the source namespaces. Virtual references are canonical IDs: a
// dependency parameter is its ID (above every source token), a value or a
// projection is CT_ROW_BASE + its record. Parameter references are checked
// against the returned limit, which admits the parameter IDs.
public bool canonical_constant_view_ranges(out uint parameters, out uint projections,
    out uint parameter_limit)
{
    parameter_limit = 0u;
    uint stride; uint slots;
    type_const_param_scalar_by_token.GetDimensions(parameters, stride);
    type_const_param_slot_by_token.GetDimensions(slots, stride);
    checked_constant_projections.GetDimensions(projections, stride);
    // The two source tables address the same declaration-token namespace.
    if (parameters != slots || parameters > CT_ROW_BASE || projections > CT_ROW_BASE) return false;
    parameter_limit = CT_UNKNOWN;
    return true;
}

// The virtual reference of canonical constant `id`.
uint2 canonical_constant_view_operand(uint id)
{
    if (ct_is_dep_param(id) && ct_is_const_param(id)) return uint2(2u, id);
    uint kind = ct_kind(id);
    if (kind == CC_KIND_VALUE) return uint2(1u, CT_ROW_BASE + id);
    return kind == CC_KIND_CAST ? uint2(3u, CT_ROW_BASE + id) : uint2(0u, 0xffffffffu);
}

public bool canonical_constant_view_reference<Graph : IScopedTypeGraph>(uint type,
    out uint2 reference)
{
    reference = uint2(0u, 0xffffffffu);
    uint id = canonical_constant_id(type);
    // Pages were interned by earlier dispatches.
    if (!ct_is_resolved(id)) return false;
    reference = canonical_constant_view_operand(id);
    // A literal keeps its caller-owned source atom.
    if (dependency_type_word(type * 9u) != 9u) return reference.y != 0xffffffffu;
    uint size; uint stride;
    dependency_constant_ref_by_type.GetDimensions(size, stride);
    uint3 source_value;
    uint2 mapped = type < size ? dependency_constant_ref_by_type[type] : uint2(0u, 0xffffffffu);
    reference = mapped;
    return ct_kind(id) == CC_KIND_VALUE && mapped.x == 1u && Graph.constant_value(mapped.y, source_value) &&
        constant_values_equal(ct_words(id), source_value);
}

public struct CanonicalConstantGraph<Graph : IScopedTypeGraph> : IConstantIdentityGraph
{
    static bool constant_value(uint row, out uint3 value)
    {
        if (row < CT_ROW_BASE) return Graph.constant_value(row, value);
        uint id = row - CT_ROW_BASE;
        bool valid = ct_kind(id) == CC_KIND_VALUE;
        value = valid ? ct_words(id) : uint3(0u, 0u, 0u);
        return valid;
    }

    static uint constant_parameter_scalar(uint reference)
    {
        uint parameters; uint projections; uint limit;
        if (!canonical_constant_view_ranges(parameters, projections, limit)) return 0u;
        if (reference < parameters)
            return Graph.parameter_is_valid(reference, true) ? Graph.constant_parameter_scalar(reference) : 0u;
        return ct_is_dep_param(reference) && ct_is_const_param(reference) ? ct_dep_param_scalar(reference) : 0u;
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
        uint id = row - CT_ROW_BASE;
        if (row < CT_ROW_BASE || ct_kind(id) != CC_KIND_CAST) return false;
        target = ct_words(id).x;
        child = canonical_constant_view_operand(ct_arg(id, 0u));
        return child.y != 0xffffffffu;
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
        bool source = reference < parameters;
        if (!source && (!ct_is_dep_param(reference) || !ct_is_const_param(reference) ||
            environment == 0xffffffffu)) return false;
        uint scalar = source ? 0u : ct_dep_param_scalar(reference);
        if (source ? !Graph.parameter_is_valid(reference, true) ||
                !Graph.substitute_constant_parameter(environment, reference, kind, payload)
            : !constant_scalar_is_supported(scalar) ||
                !Graph.environment_constant(environment, ct_dep_param_slot(reference), kind, payload))
            return false;
        // Only caller-owned source references leave the imported environment.
        uint bound = constant_reference_scalar<Graph>(uint2(kind, payload));
        return (kind != 2u || payload < parameters) && (kind != 3u || payload < projections) &&
            (source ? constant_scalar_is_supported(bound) : bound == scalar);
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
