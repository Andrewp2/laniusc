import primitive_types;
import constant_value;
import type_checker.concrete_type_equality;
// Inference returns pure requests. Only the publication pass allocates rows.
// Ordinary constants retain typed identity; array counts request explicit
// conversions whose pending fit obligations stay in their original graphs.
import type_checker.scoped_type_equality;

public struct InferredConstant
{
    public uint2 reference;
    // Zero: retain the caller-owned reference. Otherwise publish a new
    // CountProjection(target_scalar, reference), never relabel the source.
    public uint target_scalar;
    // Identity belongs to the evidence, not the reference storage kind.
    // 0: ordinary typed identity. 1: an array-count constraint, whose original
    // source graph retains every fit obligation after this request is merged.
    public uint identity_mode;
}

public struct InferredConstantDescriptor
{
    public ConstantReferenceDescriptor source;
    public uint target_scalar;
    public uint result_scalar;
    public uint pending_fit;
    // Defined only when source.disposition is CONSTANT_REFERENCE_CONCRETE.
    public uint3 value;
}

public InferredConstant inferred_constant_reference(uint2 reference)
{
    InferredConstant request;
    request.reference = reference; request.target_scalar = 0u; request.identity_mode = 0u;
    return request;
}

public bool inferred_constant_request_descriptor<Graph : IParameterScopedTypeGraph>(
    InferredConstant request, uint tokens, out InferredConstantDescriptor descriptor)
{
    descriptor = (InferredConstantDescriptor)0;
    if (request.identity_mode > 1u) return false;
    uint3 root = uint3(request.reference, 0xffffffffu);
    if (!scoped_constant_reference<Graph>(root, tokens, descriptor.source) ||
        !constant_descriptor_result_scalar<Graph>(descriptor.source, descriptor.result_scalar)) return false;
    descriptor.target_scalar = request.target_scalar;
    descriptor.value = descriptor.source.value;
    descriptor.pending_fit = descriptor.source.pending_fit;
    if (request.target_scalar == 0u)
        return request.identity_mode == 0u || scalar_is_integer(descriptor.result_scalar);
    if (!scalar_is_integer(request.target_scalar) || !scalar_is_integer(descriptor.result_scalar) ||
        descriptor.source.steps >= CONSTANT_REFERENCE_WORK_LIMIT) return false;
    if (descriptor.source.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        uint count;
        if (!constant_value_to_count(descriptor.source.value, count) ||
            !constant_value_from_count(count, request.target_scalar, descriptor.value)) return false;
    }
    else descriptor.pending_fit = 1u;
    descriptor.result_scalar = request.target_scalar;
    return true;
}

public bool inferred_constant_request_value<Graph : IParameterScopedTypeGraph>(
    InferredConstant request, uint tokens, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    InferredConstantDescriptor descriptor;
    if (!inferred_constant_request_descriptor<Graph>(request, tokens, descriptor) ||
        descriptor.source.disposition != CONSTANT_REFERENCE_CONCRETE || descriptor.pending_fit != 0u)
        return false;
    value = descriptor.value; return true;
}

// The optional prefix is a pure request, not a virtual graph row. Once
// consumed, traversal continues through the immutable caller-owned reference.
uint inferred_constant_identity_step<Graph : IParameterScopedTypeGraph>(
    inout uint prefix, inout uint3 reference, uint tokens, out uint3 next, out uint scalar)
{
    if (prefix != 0u)
    {
        scalar = prefix; prefix = 0u; next = reference; return 3u;
    }
    return constant_identity_step<Graph, ScopedConstantEnvironment<Graph>>(reference, tokens, next, scalar);
}

// Both descriptors were admitted from immutable source graphs. Comparing
// their values and retained recipes does not require inspecting them again.
bool inferred_constant_descriptors_equal<Graph : IParameterScopedTypeGraph>(
    InferredConstantDescriptor a, InferredConstantDescriptor b, uint tokens, bool count_identity)
{
    if (a.source.disposition != b.source.disposition) return false;
    if (a.source.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        if (!count_identity) return constant_values_equal(a.value, b.value);
        uint left_count; uint right_count;
        return constant_value_to_count(a.value, left_count) &&
            constant_value_to_count(b.value, right_count) && left_count == right_count;
    }
    if (count_identity)
        return scalar_is_integer(a.source.terminal_scalar) &&
            a.source.terminal_scalar == b.source.terminal_scalar &&
            all(a.source.terminal == b.source.terminal);
    if (a.result_scalar != b.result_scalar) return false;
    uint3 left_ref = a.source.root; uint3 right_ref = b.source.root;
    uint left_prefix = a.target_scalar; uint right_prefix = b.target_scalar;
    // At most one request prefix followed by an admitted 64-step source chain.
    for (uint work = 0u; work <= CONSTANT_REFERENCE_WORK_LIMIT; work++)
    {
        uint3 left_next; uint3 right_next; uint left_scalar; uint right_scalar;
        uint left_step = inferred_constant_identity_step<Graph>(left_prefix, left_ref, tokens, left_next, left_scalar);
        uint right_step = inferred_constant_identity_step<Graph>(right_prefix, right_ref, tokens, right_next, right_scalar);
        if (left_step != right_step || left_scalar != right_scalar) return false;
        if (left_step == 2u) return left_ref.y == right_ref.y;
        if (left_step != 3u) return false;
        left_ref = left_next; right_ref = right_next;
    }
    return false;
}

public bool inferred_constant_requests_equal<Graph : IParameterScopedTypeGraph>(
    InferredConstant left, InferredConstant right, uint tokens, bool count_identity = false)
{
    InferredConstantDescriptor a; InferredConstantDescriptor b;
    return inferred_constant_request_descriptor<Graph>(left, tokens, a) &&
        inferred_constant_request_descriptor<Graph>(right, tokens, b) &&
        inferred_constant_descriptors_equal<Graph>(a, b, tokens, count_identity);
}

// Merging evidence is distinct from ordinary constant equality. Count
// provenance authorizes count comparison only for this merge and only within
// one declared result scalar. An exact claim always wins over a count claim.
public bool inferred_constant_claims_compatible<Graph : IParameterScopedTypeGraph>(
    InferredConstant left, InferredConstant right, uint tokens)
{
    InferredConstantDescriptor a; InferredConstantDescriptor b;
    return inferred_constant_request_descriptor<Graph>(left, tokens, a) &&
        inferred_constant_request_descriptor<Graph>(right, tokens, b) &&
        a.result_scalar == b.result_scalar &&
        inferred_constant_descriptors_equal<Graph>(a, b, tokens,
            left.identity_mode == 1u || right.identity_mode == 1u);
}

public bool merge_inferred_constant_claim<Graph : IParameterScopedTypeGraph>(
    inout InferredConstant retained, InferredConstant candidate, uint tokens)
{
    if (!inferred_constant_claims_compatible<Graph>(retained, candidate, tokens)) return false;
    if (candidate.identity_mode < retained.identity_mode) retained = candidate;
    return true;
}

public bool inferred_constant_matches_reference<Graph : IParameterScopedTypeGraph>(
    InferredConstant request, uint2 reference, uint tokens, bool count_identity = false)
{
    return inferred_constant_requests_equal<Graph>(request,
        inferred_constant_reference(reference), tokens, count_identity);
}

public bool checked_constant_reference<Graph : IScopedTypeGraph>(uint2 reference, uint tokens)
{
    uint3 scoped = uint3(reference, 0xffffffffu);
    ConstantReferenceDescriptor descriptor;
    return scoped_constant_reference<Graph>(scoped, tokens, descriptor);
}

// A unary projection retains its original parameter occurrence even when its
// result scalar differs. No target scalar is substituted for that declaration.
public bool constant_reference_parameter_mask<Graph : IScopedTypeGraph>(
    uint2 reference, uint tokens, out uint mask)
{
    mask = 0u;
    uint3 root = uint3(reference, 0xffffffffu);
    ConstantReferenceDescriptor descriptor;
    if (!scoped_constant_reference<Graph>(root, tokens, descriptor)) return false;
    if (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE) return true;
    uint slot = Graph.constant_parameter_slot(descriptor.terminal.y);
    if (slot >= 32u) return false;
    mask = 1u << slot;
    return true;
}

// The caller validates the exact source/imported declaration and selects its
// own constant slot. No imported member is fabricated as a declaration token.
public bool constant_parameter_constraint<Graph : IScopedTypeGraph>(
    uint declared_scalar, uint slot, uint environment, uint2 actual, uint tokens,
    bool infer_unbound, inout InferredConstant inferred[32], inout uint mask)
{
    if (slot >= 32u || !constant_scalar_is_supported(declared_scalar)) return false;
    InferredConstant candidate = inferred_constant_reference(actual);
    InferredConstantDescriptor descriptor;
    if (!inferred_constant_request_descriptor<Graph>(candidate, tokens, descriptor) ||
        descriptor.result_scalar != declared_scalar) return false;
    uint2 bound;
    if (Graph.environment_constant(environment, slot, bound.x, bound.y))
        return inferred_constant_matches_reference<Graph>(candidate, bound, tokens);
    if (!infer_unbound) return false;
    uint bit = 1u << slot;
    if ((mask & bit) == 0u)
    {
        inferred[slot] = candidate;
        mask |= bit;
    }
    return merge_inferred_constant_claim<Graph>(inferred[slot], candidate, tokens);
}

public bool array_count_parameter_constraint<Graph : IScopedTypeGraph>(
    uint declared_scalar, uint slot, uint environment, uint2 actual, uint tokens,
    bool infer_unbound, inout InferredConstant inferred[32], inout uint mask, uint identity_mode = 1u)
{
    if (slot >= 32u || !scalar_is_integer(declared_scalar)) return false;
    InferredConstant candidate = inferred_constant_reference(actual);
    candidate.identity_mode = identity_mode;
    InferredConstantDescriptor descriptor;
    if (!inferred_constant_request_descriptor<Graph>(candidate, tokens, descriptor) ||
        !scalar_is_integer(descriptor.result_scalar)) return false;
    if (descriptor.source.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        uint count; uint3 converted;
        if (!constant_value_to_count(descriptor.value, count) ||
            !constant_value_from_count(count, declared_scalar, converted)) return false;
    }
    if (descriptor.result_scalar != declared_scalar) candidate.target_scalar = declared_scalar;
    // Admission of this request retains every existing projection in source.
    // A fresh conversion is an explicit pure request for the publishing pass.
    if (!inferred_constant_request_descriptor<Graph>(candidate, tokens, descriptor)) return false;
    uint2 bound;
    if (Graph.environment_constant(environment, slot, bound.x, bound.y))
    {
        InferredConstantDescriptor bound_descriptor;
        if (!inferred_constant_request_descriptor<Graph>(inferred_constant_reference(bound),
            tokens, bound_descriptor) || bound_descriptor.result_scalar != declared_scalar) return false;
        return inferred_constant_matches_reference<Graph>(candidate, bound, tokens, identity_mode == 1u);
    }
    if (!infer_unbound) return false;
    uint bit = 1u << slot;
    if ((mask & bit) == 0u)
    {
        inferred[slot] = candidate;
        mask |= bit;
    }
    // Exact evidence has priority over array-only evidence. Every original
    // actual graph still owns its pending fits after this binding is selected.
    InferredConstantDescriptor retained;
    if (!inferred_constant_request_descriptor<Graph>(inferred[slot], tokens, retained) ||
        retained.result_scalar != declared_scalar) return false;
    return merge_inferred_constant_claim<Graph>(inferred[slot], candidate, tokens);
}

// Array patterns may themselves contain inferred conversion recipes. Infer
// their exact terminal declaration while retaining every outer fit obligation
// in the original pattern graph for instantiated normalization.
public bool array_count_reference_constraint<Graph : IScopedTypeGraph>(uint2 pattern,
    uint environment, uint2 actual, uint tokens, bool infer_unbound,
    inout InferredConstant inferred[32], inout uint mask, bool same_scope_identity = true)
{
    uint3 open_pattern = uint3(pattern, 0xffffffffu);
    ConstantReferenceDescriptor pattern_descriptor;
    if (!scoped_constant_reference<Graph>(open_pattern, tokens, pattern_descriptor)) return false;
    // A concrete pattern, a bound parameter, or an unbound parameter compared
    // in its own scope (environment is then 0xffffffff, so the scoped pattern
    // equals open_pattern) is a count comparison, made at one call site.
    bool compare_counts = pattern_descriptor.disposition == CONSTANT_REFERENCE_CONCRETE;
    uint parameter = pattern_descriptor.terminal.y;
    uint slot = 0xffffffffu;
    if (!compare_counts)
    {
        slot = Graph.constant_parameter_slot(parameter);
        if (slot >= 32u || !scalar_is_integer(pattern_descriptor.terminal_scalar)) return false;
        uint2 bound;
        if (Graph.environment_constant(environment, slot, bound.x, bound.y)) compare_counts = true;
        else if (!infer_unbound)
        {
            if (!same_scope_identity || environment != 0xffffffffu) return false;
            compare_counts = true;
        }
    }
    if (compare_counts)
        return scoped_constant_counts_equal<Graph, Graph>(
            uint3(pattern, environment), uint3(actual, 0xffffffffu), tokens);

    InferredConstantDescriptor candidate;
    if (!inferred_constant_request_descriptor<Graph>(inferred_constant_reference(actual),
        tokens, candidate) || !scalar_is_integer(candidate.result_scalar)) return false;
    if (candidate.source.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        uint count;
        if (!constant_value_to_count(candidate.value, count)) return false;
        uint3 reference = open_pattern;
        bool reached_parameter = false;
        for (uint work = 0u; work < CONSTANT_REFERENCE_WORK_LIMIT; work++)
        {
            uint3 next; uint scalar;
            uint step = constant_identity_step<Graph, ScopedConstantEnvironment<Graph>>(
                reference, tokens, next, scalar);
            if (step == 2u) { reached_parameter = reference.y == parameter; break; }
            uint3 converted;
            if (step != 3u || !constant_value_from_count(count, scalar, converted)) return false;
            reference = next;
        }
        if (!reached_parameter) return false;
    }
    return array_count_parameter_constraint<Graph>(pattern_descriptor.terminal_scalar,
        slot, environment, actual, tokens, true, inferred, mask);
}

public bool constant_reference_constraint<Graph : IScopedTypeGraph>(uint2 pattern,
    uint slot, uint environment, uint2 actual, uint tokens, bool infer_unbound,
    inout InferredConstant inferred[32], inout uint mask, bool same_scope_identity = true)
{
    // A non-parameter pattern and a same-scope unbound parameter share one
    // typed-identity comparison call.
    if (pattern.x == 2u)
    {
        if (pattern.y >= tokens || slot >= 32u ||
            !Graph.parameter_is_valid(pattern.y, true)) return false;
        if (infer_unbound || environment != 0xffffffffu || !same_scope_identity)
            return constant_parameter_constraint<Graph>(Graph.constant_parameter_scalar(pattern.y),
                slot, environment, actual, tokens, infer_unbound, inferred, mask);
    }
    return scoped_constant_refs_equal<Graph, Graph>(
        uint3(pattern, environment), uint3(actual, 0xffffffffu), tokens);
}
