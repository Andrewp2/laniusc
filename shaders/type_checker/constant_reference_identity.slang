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
// Read 0 classifies `reference`; after a substitution, read 1 takes only the
// substituted reference's scalar (constant_reference_scalar of it) through
// the same graph reads.
public uint constant_reference_step<Graph : IConstantIdentityGraph, Environment : IConstantReferenceEnvironment>(
    uint3 reference, uint tokens, out uint3 next, out uint scalar, out uint3 value)
{
    next = uint3(0u, 0xffffffffu, 0xffffffffu);
    scalar = 0u; value = uint3(0u, 0u, 0u);
    uint2 subject = reference.xy;
    [loop]
    for (uint read = 0u; read < 2u; read++)
    {
        // A substituted INVALID payload has scalar 0, never the parameter's.
        if (subject.y == 0xffffffffu) return 0u;
        uint3 read_value = uint3(0u, 0u, 0u); uint read_scalar = 0u;
        uint2 child = uint2(0u, 0xffffffffu); bool known;
        if (subject.x == 1u)
        {
            known = Graph.constant_value(subject.y, read_value) && constant_value_is_valid(read_value);
            read_scalar = read_value.x;
        }
        else if (subject.x == 2u)
        {
            read_scalar = Graph.constant_parameter_scalar(subject.y);
            known = constant_scalar_is_supported(read_scalar);
        }
        else
            known = subject.x == 3u && Graph.constant_projection(subject.y, read_scalar, child) &&
                scalar_is_integer(read_scalar);
        if (read != 0u)
        {
            if (!known || read_scalar != scalar) return 0u;
            next = uint3(subject, 0xffffffffu);
            return 4u;
        }
        if (subject.x == 1u)
        {
            value = read_value;
            if (!known) return 0u;
            scalar = read_scalar; return 1u;
        }
        scalar = read_scalar;
        if (subject.x == 2u)
        {
            if (reference.y >= tokens || !known || !Environment.parameter_is_valid(reference.y)) return 0u;
            if (reference.z == 0xffffffffu) return 2u;
            uint kind; uint payload;
            if (!Environment.substitute(reference.z, reference.y, kind, payload)) return 0u;
            subject = uint2(kind, payload);
            continue;
        }
        if (!known || child.x < 1u || child.x > 3u || child.y == 0xffffffffu) return 0u;
        next = uint3(child, reference.z);
        return 3u;
    }
    return 0u;
}

// Inspection as resumable state: constant_inspection_feed consumes the
// result of constant_reference_step(inspection.reference). Validation (pass 0)
// and concrete-fit replay (pass 1) are two ordered passes, each bounded by
// CONSTANT_REFERENCE_WORK_LIMIT steps. inspect_constant_reference drives it
// through one step call site; the scoped identity hash and equality
// (scoped_type_equality.slang) drive it and their identity walks through the
// same site, so a walker expands each graph's step reader once.
public static const uint CONSTANT_INSPECTION_RUNNING = 0u;
public static const uint CONSTANT_INSPECTION_ACCEPTED = 1u;
public static const uint CONSTANT_INSPECTION_REJECTED = 2u;

public struct ConstantInspection
{
    public ConstantReferenceDescriptor descriptor;
    public uint3 reference;
    public uint3 checkpoint;
    public uint span;
    public uint since;
    public uint outer_scalar;
    public uint count;
    public uint pass;
    public uint work;
    public uint result;
}

public ConstantInspection constant_inspection_begin(uint3 reference)
{
    ConstantInspection inspection = (ConstantInspection)0;
    inspection.descriptor.root = reference;
    inspection.descriptor.terminal = uint2(0u, 0xffffffffu);
    inspection.reference = reference;
    inspection.checkpoint = reference;
    inspection.span = 1u;
    return inspection;
}

public void constant_inspection_feed(inout ConstantInspection inspection, uint step, uint3 next,
    uint scalar, uint3 value)
{
    uint result = CONSTANT_INSPECTION_RUNNING;
    if (inspection.pass != 0u)
    {
        uint3 fitted;
        if (step == 0u || step == 2u) result = CONSTANT_INSPECTION_REJECTED;
        else if (step == 1u)
            result = constant_value_from_count(inspection.count, inspection.outer_scalar,
                inspection.descriptor.value) ? CONSTANT_INSPECTION_ACCEPTED : CONSTANT_INSPECTION_REJECTED;
        else if (step == 3u && !constant_value_from_count(inspection.count, scalar, fitted))
            result = CONSTANT_INSPECTION_REJECTED;
        else inspection.reference = next;
    }
    else if (step == 0u) result = CONSTANT_INSPECTION_REJECTED;
    else if (step == 1u || step == 2u)
    {
        inspection.descriptor.disposition = step;
        inspection.descriptor.steps = inspection.work + 1u;
        inspection.descriptor.value = value;
        inspection.descriptor.terminal = inspection.reference.xy;
        inspection.descriptor.terminal_scalar = scalar;
        if (inspection.outer_scalar != 0u && !scalar_is_integer(scalar))
            result = CONSTANT_INSPECTION_REJECTED;
        else
        {
            inspection.descriptor.pending_fit = step == 2u && inspection.outer_scalar != 0u ? 1u : 0u;
            if (step == CONSTANT_REFERENCE_SYMBOLIC || inspection.outer_scalar == 0u)
                result = CONSTANT_INSPECTION_ACCEPTED;
            else if (!constant_value_to_count(inspection.descriptor.value, inspection.count))
                result = CONSTANT_INSPECTION_REJECTED;
            else
            {
                // Replay the admitted chain from the (rewritten) root.
                inspection.reference = inspection.descriptor.root;
                inspection.pass = 1u; inspection.work = 0u;
                return;
            }
        }
    }
    else
    {
        if (step == 3u && inspection.outer_scalar == 0u) inspection.outer_scalar = scalar;
        // Rewrite only a bare root substitution. A projection's environment
        // is needed when its original child is reached by subsequent readers.
        if (inspection.work == 0u && step == 4u) inspection.descriptor.root = next;
        // Brent's cycle check uses constant storage. The independent work cap
        // also bounds long acyclic chains and malformed substitution graphs.
        if (all(next == inspection.checkpoint)) result = CONSTANT_INSPECTION_REJECTED;
        else
        {
            inspection.since++;
            if (inspection.since == inspection.span)
            { inspection.checkpoint = next; inspection.span *= 2u; inspection.since = 0u; }
            inspection.reference = next;
        }
    }
    if (result == CONSTANT_INSPECTION_RUNNING)
    {
        inspection.work++;
        if (inspection.work == CONSTANT_REFERENCE_WORK_LIMIT) result = CONSTANT_INSPECTION_REJECTED;
    }
    inspection.result = result;
}

public bool inspect_constant_reference<Graph : IConstantIdentityGraph,
    Environment : IConstantReferenceEnvironment>(uint3 reference, uint tokens,
    out ConstantReferenceDescriptor descriptor)
{
    ConstantInspection inspection = constant_inspection_begin(reference);
    // Each feed ends the inspection or advances a pass's work: two passes.
    [loop]
    for (uint guard = 0u; guard <= 2u * CONSTANT_REFERENCE_WORK_LIMIT &&
        inspection.result == CONSTANT_INSPECTION_RUNNING; guard++)
    {
        uint3 next; uint scalar; uint3 value;
        uint step = constant_reference_step<Graph, Environment>(inspection.reference, tokens, next, scalar, value);
        constant_inspection_feed(inspection, step, next, scalar, value);
    }
    descriptor = inspection.descriptor;
    return inspection.result == CONSTANT_INSPECTION_ACCEPTED;
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

// The identity result decided by the descriptors alone (0 different, 1
// equal) or 2: compare the identity walks from both roots.
public static const uint CONSTANT_IDENTITY_WALK = 2u;
public uint constant_descriptors_equal_prelude(ConstantReferenceDescriptor left,
    ConstantReferenceDescriptor right, bool count_identity)
{
    if (left.disposition != right.disposition) return 0u;
    if (left.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        if (!count_identity) return uint(constant_values_equal(left.value, right.value));
        uint a; uint b;
        return uint(constant_value_to_count(left.value, a) && constant_value_to_count(right.value, b) && a == b);
    }
    if (left.disposition != CONSTANT_REFERENCE_SYMBOLIC) return 0u;
    if (count_identity)
    {
        // Every projection was admitted above and retains its own fit duty.
        // Count identity is the underlying parameter, not its conversion path.
        return uint(scalar_is_integer(left.terminal_scalar) &&
            left.terminal_scalar == right.terminal_scalar &&
            all(left.terminal == right.terminal));
    }
    return CONSTANT_IDENTITY_WALK;
}

public bool constant_reference_descriptors_equal<
    LeftGraph : IConstantIdentityGraph, LeftEnvironment : IConstantReferenceEnvironment,
    RightGraph : IConstantIdentityGraph, RightEnvironment : IConstantReferenceEnvironment>(
    ConstantReferenceDescriptor left, ConstantReferenceDescriptor right, uint tokens, bool count_identity)
{
    uint prelude = constant_descriptors_equal_prelude(left, right, count_identity);
    if (prelude != CONSTANT_IDENTITY_WALK) return prelude == 1u;
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

// The hash decided by the descriptor alone (0 invalid, 1 final `hash`) or 2:
// continue `hash` with the identity walk from descriptor.root.
public uint constant_descriptor_hash_prelude(ConstantReferenceDescriptor descriptor,
    bool count_identity, out uint hash)
{
    hash = constant_identity_hash_mix(2166136261u, descriptor.disposition);
    if (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        if (count_identity)
        {
            uint count;
            if (!constant_value_to_count(descriptor.value, count)) return 0u;
            hash = constant_identity_hash_mix(hash, count);
        }
        else
            for (uint field = 0u; field < 3u; field++) hash = constant_identity_hash_mix(hash, descriptor.value[field]);
        return 1u;
    }
    if (descriptor.disposition != CONSTANT_REFERENCE_SYMBOLIC) return 0u;
    if (count_identity)
    {
        if (!scalar_is_integer(descriptor.terminal_scalar) || descriptor.terminal.x != 2u) return 0u;
        hash = constant_identity_hash_mix(hash, descriptor.terminal.x);
        hash = constant_identity_hash_mix(hash, descriptor.terminal_scalar);
        hash = constant_identity_hash_mix(hash, descriptor.terminal.y);
        return 1u;
    }
    return CONSTANT_IDENTITY_WALK;
}

public bool constant_reference_descriptor_hash<Graph : IConstantIdentityGraph,
    Environment : IConstantReferenceEnvironment>(ConstantReferenceDescriptor descriptor,
    uint tokens, bool count_identity, out uint result)
{
    result = 0u;
    uint hash;
    uint prelude = constant_descriptor_hash_prelude(descriptor, count_identity, hash);
    if (prelude != CONSTANT_IDENTITY_WALK)
    {
        if (prelude == 1u) result = hash;
        return prelude == 1u;
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
