// Included after IConstantIdentityGraph. Constant storage rows are addresses only.
// One unary walker serves immutable graphs with and without scoped bindings.
public static const uint CONSTANT_REFERENCE_CONCRETE = 1u;
public static const uint CONSTANT_REFERENCE_SYMBOLIC = 2u;
public static const uint CONSTANT_REFERENCE_WORK_LIMIT = 64u;

public struct ConstantReferenceDescriptor
{
    // (kind, payload, environment). A substituted root is caller scoped;
    // a projection keeps its original environment until its child is visited.
    public uint3 root;
    public uint disposition;
    public uint3 value;
    public uint2 terminal;
    public uint terminal_scalar;
    // Symbolic projections retain a fit obligation. Inspection is not proof
    // that every later substitution fits the target scalar or count domain.
    public uint pending_fit;
    // Inspection work includes projection edges, substitution edges and leaf.
    public uint steps;
}

public interface IConstantReferenceEnvironment
{
    static bool parameter_is_valid(uint reference);
    static bool substitute(uint environment, uint reference, out uint kind, out uint payload);
}

public struct UnboundConstantEnvironment<Graph : IConstantIdentityGraph> : IConstantReferenceEnvironment
{
    static bool parameter_is_valid(uint reference)
    { return constant_scalar_is_supported(Graph.constant_parameter_scalar(reference)); }
    static bool substitute(uint environment, uint reference, out uint kind, out uint payload)
    { kind = 0u; payload = 0xffffffffu; return false; }
}

public uint constant_identity_hash_mix(uint hash, uint value)
{
    hash = (hash ^ value) * 16777619u;
    return hash ^ (hash >> 16u);
}

public uint constant_reference_scalar<Graph : IConstantIdentityGraph>(uint2 reference)
{
    if (reference.y == 0xffffffffu) return 0u;
    if (reference.x == 1u)
    {
        uint3 value;
        return Graph.constant_value(reference.y, value) && constant_value_is_valid(value)
            ? value.x : 0u;
    }
    if (reference.x == 2u)
    {
        uint scalar = Graph.constant_parameter_scalar(reference.y);
        return constant_scalar_is_supported(scalar) ? scalar : 0u;
    }
    uint scalar; uint2 child;
    return reference.x == 3u && Graph.constant_projection(reference.y, scalar, child) &&
        scalar_is_integer(scalar) ? scalar : 0u;
}

// 0 invalid; 1 concrete leaf; 2 symbolic leaf; 3 projection; 4 substitution.
// Each successful edge advances in exactly one immutable graph namespace.
public uint constant_reference_step<Graph : IConstantIdentityGraph, Environment : IConstantReferenceEnvironment>(
    uint3 reference, uint tokens, out uint3 next, out uint scalar, out uint3 value)
{
    next = uint3(0u, 0xffffffffu, 0xffffffffu);
    scalar = 0u; value = uint3(0u, 0u, 0u);
    if (reference.y == 0xffffffffu) return 0u;
    if (reference.x == 1u)
    {
        if (!Graph.constant_value(reference.y, value) || !constant_value_is_valid(value)) return 0u;
        scalar = value.x; return 1u;
    }
    if (reference.x == 2u)
    {
        scalar = Graph.constant_parameter_scalar(reference.y);
        if (reference.y >= tokens || !constant_scalar_is_supported(scalar) ||
            !Environment.parameter_is_valid(reference.y)) return 0u;
        if (reference.z == 0xffffffffu) return 2u;
        uint2 bound;
        if (!Environment.substitute(reference.z, reference.y, bound.x, bound.y) ||
            constant_reference_scalar<Graph>(bound) != scalar) return 0u;
        next = uint3(bound, 0xffffffffu);
        return 4u;
    }
    uint2 child;
    if (reference.x != 3u || !Graph.constant_projection(reference.y, scalar, child) ||
        !scalar_is_integer(scalar) || child.x < 1u || child.x > 3u || child.y == 0xffffffffu) return 0u;
    next = uint3(child, reference.z);
    return 3u;
}

public bool inspect_constant_reference<Graph : IConstantIdentityGraph,
    Environment : IConstantReferenceEnvironment>(uint3 reference, uint tokens,
    out ConstantReferenceDescriptor descriptor)
{
    descriptor = (ConstantReferenceDescriptor)0;
    descriptor.root = reference;
    descriptor.terminal = uint2(0u, 0xffffffffu);
    uint3 checkpoint = reference;
    uint span = 1u; uint since = 0u;
    uint outer_scalar = 0u; bool leaf = false;
    uint count = 0u;
    // Keep validation and concrete-fit replay as two ordered bounded passes.
    // Sharing the step call prevents the driver from expanding the same
    // graph/environment reader once for each pass at every caller.
    [loop]
    for (uint pass = 0u; pass < 2u; pass++)
    {
        [loop]
        for (uint work = 0u; work < CONSTANT_REFERENCE_WORK_LIMIT; work++)
        {
            uint3 next; uint scalar; uint3 value;
            uint step = constant_reference_step<Graph, Environment>(reference, tokens, next, scalar, value);
            if (pass != 0u)
            {
                if (step == 0u || step == 2u) return false;
                if (step == 1u)
                    return constant_value_from_count(count, outer_scalar, descriptor.value);
                if (step == 3u && !constant_value_from_count(count, scalar, value)) return false;
                reference = next;
                continue;
            }
            if (step == 0u) return false;
            if (step == 1u || step == 2u)
            {
                descriptor.disposition = step;
                descriptor.steps = work + 1u;
                descriptor.value = value;
                descriptor.terminal = reference.xy;
                descriptor.terminal_scalar = scalar;
                if (outer_scalar != 0u && !scalar_is_integer(scalar)) return false;
                descriptor.pending_fit = step == 2u && outer_scalar != 0u ? 1u : 0u;
                leaf = true; break;
            }
            if (step == 3u && outer_scalar == 0u) outer_scalar = scalar;
            // Rewrite only a bare root substitution. A projection's environment
            // is needed when its original child is reached by subsequent readers.
            if (work == 0u && step == 4u) descriptor.root = next;
            // Brent's cycle check uses constant storage. The independent work cap
            // also bounds long acyclic chains and malformed substitution graphs.
            if (all(next == checkpoint)) return false;
            since++;
            if (since == span) { checkpoint = next; span *= 2u; since = 0u; }
            reference = next;
        }
        if (pass != 0u || !leaf) return false;
        if (descriptor.disposition == CONSTANT_REFERENCE_SYMBOLIC || outer_scalar == 0u) return true;
        if (!constant_value_to_count(descriptor.value, count)) return false;
        reference = descriptor.root;
    }
    return false;
}

// Read the resulting typed scalar while retaining the descriptor's pending
// fit obligation. A symbolic projection's outer target is declared by its row;
// its source parameter is never relabeled to that target.
public bool constant_descriptor_result_scalar<Graph : IConstantIdentityGraph>(
    ConstantReferenceDescriptor descriptor, out uint scalar)
{
    scalar = 0u;
    if (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        if (!constant_value_is_valid(descriptor.value)) return false;
        scalar = descriptor.value.x; return true;
    }
    if (descriptor.disposition != CONSTANT_REFERENCE_SYMBOLIC) return false;
    if (descriptor.root.x == 2u)
    {
        scalar = descriptor.terminal_scalar;
        return constant_scalar_is_supported(scalar);
    }
    uint2 child;
    return descriptor.root.x == 3u &&
        Graph.constant_projection(descriptor.root.y, scalar, child) && scalar_is_integer(scalar);
}

// Skip the sole declaration-to-caller substitution without discarding any
// projection node. Used only after the bounded inspection admitted the chain.
public uint constant_identity_step<Graph : IConstantIdentityGraph, Environment : IConstantReferenceEnvironment>(
    inout uint3 reference, uint tokens, out uint3 next, out uint scalar)
{
    uint3 value;
    uint step = 0u;
    // Follow at most the same one declaration-to-caller substitution, using
    // one reader call site. The second result is returned even if malformed.
    [loop]
    for (uint read = 0u; read < 2u; read++)
    {
        step = constant_reference_step<Graph, Environment>(reference, tokens, next, scalar, value);
        if (read != 0u || step != 4u) return step;
        reference = next;
    }
    return step;
}

public bool constant_reference_descriptors_equal<
    LeftGraph : IConstantIdentityGraph, LeftEnvironment : IConstantReferenceEnvironment,
    RightGraph : IConstantIdentityGraph, RightEnvironment : IConstantReferenceEnvironment>(
    ConstantReferenceDescriptor left, ConstantReferenceDescriptor right, uint tokens, bool count_identity)
{
    if (left.disposition != right.disposition) return false;
    if (left.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        if (!count_identity) return constant_values_equal(left.value, right.value);
        uint a; uint b;
        return constant_value_to_count(left.value, a) && constant_value_to_count(right.value, b) && a == b;
    }
    if (left.disposition != CONSTANT_REFERENCE_SYMBOLIC) return false;
    if (count_identity)
    {
        // Every projection was admitted above and retains its own fit duty.
        // Count identity is the underlying parameter, not its conversion path.
        return scalar_is_integer(left.terminal_scalar) &&
            left.terminal_scalar == right.terminal_scalar &&
            all(left.terminal == right.terminal);
    }
    uint3 a = left.root; uint3 b = right.root;
    for (uint work = 0u; work < CONSTANT_REFERENCE_WORK_LIMIT; work++)
    {
        uint3 next_a; uint3 next_b; uint scalar_a; uint scalar_b;
        uint step_a = constant_identity_step<LeftGraph, LeftEnvironment>(a, tokens, next_a, scalar_a);
        uint step_b = constant_identity_step<RightGraph, RightEnvironment>(b, tokens, next_b, scalar_b);
        if (step_a != step_b || scalar_a != scalar_b) return false;
        if (step_a == 2u) return a.y == b.y;
        if (step_a != 3u) return false;
        a = next_a; b = next_b;
    }
    return false;
}

public bool constant_reference_descriptor_hash<Graph : IConstantIdentityGraph,
    Environment : IConstantReferenceEnvironment>(ConstantReferenceDescriptor descriptor,
    uint tokens, bool count_identity, out uint result)
{
    result = 0u;
    uint hash = constant_identity_hash_mix(2166136261u, descriptor.disposition);
    if (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        if (count_identity)
        {
            uint count;
            if (!constant_value_to_count(descriptor.value, count)) return false;
            hash = constant_identity_hash_mix(hash, count);
        }
        else
            for (uint field = 0u; field < 3u; field++) hash = constant_identity_hash_mix(hash, descriptor.value[field]);
        result = hash; return true;
    }
    if (descriptor.disposition != CONSTANT_REFERENCE_SYMBOLIC) return false;
    if (count_identity)
    {
        if (!scalar_is_integer(descriptor.terminal_scalar) || descriptor.terminal.x != 2u) return false;
        hash = constant_identity_hash_mix(hash, descriptor.terminal.x);
        hash = constant_identity_hash_mix(hash, descriptor.terminal_scalar);
        result = constant_identity_hash_mix(hash, descriptor.terminal.y);
        return true;
    }
    uint3 reference = descriptor.root;
    for (uint work = 0u; work < CONSTANT_REFERENCE_WORK_LIMIT; work++)
    {
        uint3 next; uint scalar;
        uint step = constant_identity_step<Graph, Environment>(reference, tokens, next, scalar);
        hash = constant_identity_hash_mix(hash, step);
        hash = constant_identity_hash_mix(hash, scalar);
        if (step == 2u)
        {
            result = constant_identity_hash_mix(hash, reference.y);
            return true;
        }
        if (step != 3u) return false;
        reference = next;
    }
    return false;
}

public bool constant_refs_equal<LeftGraph : IConstantIdentityGraph, RightGraph : IConstantIdentityGraph>(
    uint2 left, uint2 right, uint tokens, bool count_identity = false)
{
    ConstantReferenceDescriptor a; ConstantReferenceDescriptor b;
    return inspect_constant_reference<LeftGraph, UnboundConstantEnvironment<LeftGraph>>(
            uint3(left, 0xffffffffu), tokens, a) &&
        inspect_constant_reference<RightGraph, UnboundConstantEnvironment<RightGraph>>(
            uint3(right, 0xffffffffu), tokens, b) &&
        constant_reference_descriptors_equal<LeftGraph, UnboundConstantEnvironment<LeftGraph>,
            RightGraph, UnboundConstantEnvironment<RightGraph>>(a, b, tokens, count_identity);
}
