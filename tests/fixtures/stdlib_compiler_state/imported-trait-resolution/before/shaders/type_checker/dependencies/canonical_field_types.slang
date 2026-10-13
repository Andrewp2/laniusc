import type_checker.concrete_type_equality;
// Resolve declaration-side interface trees under a checked receiver. Canonical
// row numbers stay on the active page; completed applications use stable
// checked references. Hashes select buckets only, never establish equality.
import dependency_interface;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;
import type_checker.constant_constraints;

public StructuredBuffer<uint> canonical_type_roots;

public uint canonical_field_root(uint type)
{
    uint count = dependency_type_count();
    uint root = type < count ? canonical_type_roots[type] : 0xffffffffu;
    return root < count ? root : 0xffffffffu;
}

// Canonical array lengths encode a member identity, decoded to a constant slot.
// Translate at the interface boundary into the same checked call environment.
public bool canonical_constant_length<Graph : IScopedTypeGraph>(uint environment,
    uint type, inout uint kind, inout uint value)
{
    if (kind == 1u) return value != 0xffffffffu;
    if (kind != 2u) return false;
    uint slot = dependency_generic_const_slot(type);
    if (slot >= 32u) return false;
    if (!Graph.environment_constant(environment, slot, kind, value)) return false;
    return value != 0xffffffffu && (kind == 1u || kind == 2u);
}

public bool canonical_field_leaf<Graph : IScopedTypeGraph>(uint instance, inout uint2 reference)
{
    if (reference.x != 5u) return true;
    uint root = canonical_field_root(reference.y);
    if (root == 0xffffffffu) return false;
    reference.y = root;
    uint kind = dependency_type_word(root * 9u);
    if (kind == 1u)
    {
        reference = uint2(1u, dependency_type_word(root * 9u + 1u));
        return reference.y != 0u && reference.y != 0xffffffffu;
    }
    if (kind == 2u)
        return Graph.environment_argument(instance, dependency_generic_type_slot(root), reference.x, reference.y);
    if (kind == 8u || kind == 9u)
    {
        uint constant_kind = 1u; uint value = dependency_type_word(root * 9u + 1u);
        if (kind == 8u && !Graph.environment_constant(instance, dependency_generic_const_slot(root), constant_kind, value)) return false;
        reference = uint2(APPLICATION_CONSTANT_ARGUMENT | constant_kind, value);
        return application_argument_is_constant(reference.x) && value != 0xffffffffu;
    }
    uint start = dependency_type_word(root * 9u + 3u);
    uint count = dependency_type_word(root * 9u + 4u);
    uint edges = dependency_count(5u);
    if (start > edges || count > edges - start) return false;
    if (kind == 3u) return count <= 32u;
    if (kind == 4u)
        return count == 1u &&
            ((dependency_type_word(root * 9u + 5u) == 1u && dependency_type_word(root * 9u + 6u) != 0xffffffffu) ||
             (dependency_type_word(root * 9u + 5u) == 2u && dependency_generic_const_slot(root) < 32u));
    // Slices and references each own one complete child type. Their distinct
    // node kinds retain value/borrow semantics through hashing and replay.
    return (kind == 5u || kind == 6u) && count == 1u;
}

public uint2 canonical_application_domains(uint type)
{
    uint start = dependency_type_word(type * 9u + 3u);
    uint count = dependency_type_word(type * 9u + 4u);
    uint types = 0u; uint flags = 0u; uint constants = 0u; bool saw_constant = false;
    for (uint ordinal = 0u; ordinal < min(count, 32u); ordinal++)
    {
        uint child = canonical_field_root(dependency_type_edge_word(start + ordinal));
        uint kind = child < dependency_type_count() ? dependency_type_word(child * 9u) : 0u;
        if (kind == 8u || kind == 9u) { saw_constant = true; constants |= 1u << ordinal; }
        else { types++; if (saw_constant) flags = APPLICATION_INTERLEAVED_DOMAINS; }
    }
    return uint2(types | flags, constants);
}

public bool canonical_field_ref_hash<Graph : IScopedTypeGraph>(uint instance, uint type,
    uint capacity, uint tokens, out uint result)
{
    static const uint INVALID = 0xffffffffu;
    static const uint LIMIT = 64u;
    uint2 refs[LIMIT]; uint next[LIMIT]; uint counts[LIMIT];
    uint depth = 0u; uint hash = 2166136261u;
    refs[0u] = uint2(5u, type); next[0u] = INVALID;
    result = 0u;
    for (;;)
    {
        uint2 ref = refs[depth];
        if (next[depth] == INVALID)
        {
            if (!canonical_field_leaf<Graph>(instance, ref)) return false;
            refs[depth] = ref; next[depth] = 0u; counts[depth] = 0u;
            hash = scoped_type_hash_mix(hash, ref.x == 5u ? 3u : ref.x);
            if (application_argument_is_constant(ref.x))
            {
                if (ref.y == INVALID) return false;
                hash = scoped_type_hash_mix(hash, ref.y);
            }
            else if (ref.x == 1u || ref.x == 2u)
            {
                if (ref.y == 0u || ref.y == INVALID || (ref.x == 2u &&
                    (ref.y >= tokens || Graph.parameter_slot(ref.y) == INVALID))) return false;
                hash = scoped_type_hash_mix(hash, ref.y);
            }
            else if (ref.x == 3u || ref.x == 5u)
            {
                if (ref.x == 3u && ref.y >= capacity) return false;
                uint kind = ref.x == 5u ? dependency_type_word(ref.y * 9u) - 2u : Graph.metadata(ref.y, 0u);
                if (kind < 1u || kind > 4u) return false;
                hash = scoped_type_hash_mix(hash, kind);
                if (kind == 1u)
                {
                    uint declaration = ref.x == 5u ? INVALID : Graph.metadata(ref.y, 1u);
                    hash = scoped_type_hash_mix(hash, declaration);
                    if (declaration == INVALID)
                    {
                        uint3 identity = ref.x == 5u
                            ? uint3(dependency_type_word(ref.y * 9u + 1u),
                                dependency_type_word(ref.y * 9u + 8u), dependency_type_word(ref.y * 9u + 2u))
                            : uint3(Graph.metadata(ref.y, 7u), Graph.metadata(ref.y, 8u), Graph.metadata(ref.y, 9u));
                        if (any(identity == INVALID)) return false;
                        hash = scoped_type_hash_mix(hash, identity.x);
                        hash = scoped_type_hash_mix(hash, identity.y);
                        hash = scoped_type_hash_mix(hash, identity.z);
                    }
                    else if (declaration >= tokens) return false;
                    counts[depth] = ref.x == 5u ? dependency_type_word(ref.y * 9u + 4u) : Graph.metadata(ref.y, 2u);
                    if (counts[depth] > 32u) return false;
                    hash = scoped_type_hash_mix(hash, counts[depth]);
                }
                else
                {
                    if (kind == 2u)
                    {
                        uint length_kind = ref.x == 5u ? dependency_type_word(ref.y * 9u + 5u) : Graph.metadata(ref.y, 5u);
                        uint length = ref.x == 5u ? dependency_type_word(ref.y * 9u + 6u) : Graph.metadata(ref.y, 6u);
                        if (ref.x == 5u)
                        {
                            if (!canonical_constant_length<Graph>(instance, ref.y, length_kind, length)) return false;
                        }
                        else if (!scoped_constant_length<Graph>(INVALID, tokens, length_kind, length)) return false;
                        hash = scoped_type_hash_mix(hash, length_kind);
                        hash = scoped_type_hash_mix(hash, length);
                    }
                    counts[depth] = 1u;
                }
            }
            else return false;
        }
        if (next[depth] == counts[depth])
        {
            hash = scoped_type_hash_mix(hash, INVALID);
            if (depth == 0u) { result = hash; return true; }
            depth--; continue;
        }
        uint slot = next[depth]++;
        uint2 child;
        if (ref.x == 5u)
            child = uint2(5u, dependency_type_edge_word(dependency_type_word(ref.y * 9u + 3u) + slot));
        else if (Graph.metadata(ref.y, 0u) == 1u)
        {
            if (!Graph.argument(ref.y, slot, child.x, child.y)) return false;
        }
        else child = uint2(Graph.metadata(ref.y, 3u), Graph.metadata(ref.y, 4u));
        if (depth + 1u == LIMIT) return false;
        for (uint ancestor = 0u; ancestor <= depth; ancestor++)
            if (all(refs[ancestor] == child)) return false;
        depth++; refs[depth] = child; next[depth] = INVALID;
    }
}

public bool canonical_type_and_constant_constraints<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint actual_tag, uint actual_payload, uint capacity, uint tokens, bool infer_unbound,
    out uint2 inferred[32], out uint inferred_mask,
    out uint2 constants[32], out uint constant_mask, bool infer_constants,
    bool allow_root_array_to_slice = false)
{
    static const uint INVALID = 0xffffffffu;
    static const uint LIMIT = 64u;
    uint3 pairs[LIMIT]; uint next[LIMIT]; uint counts[LIMIT];
    inferred_mask = 0u;
    constant_mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++) inferred[slot] = uint2(0u, INVALID);
    for (uint slot = 0u; slot < 32u; slot++) constants[slot] = uint2(0u, INVALID);
    uint depth = 0u;
    pairs[0u] = uint3(type, actual_tag, actual_payload); next[0u] = INVALID;
    for (;;)
    {
        uint3 pair = pairs[depth];
        if (next[depth] == INVALID)
        {
            uint2 expected = uint2(5u, pair.x);
            uint root = canonical_field_root(pair.x);
            if (root == INVALID) return false;
            uint root_kind = dependency_type_word(root * 9u);
            if (root_kind == 8u || root_kind == 9u)
            {
                uint kind; uint value;
                if (!application_constant_argument(pair.y, pair.z, kind, value) ||
                    !constant_reference_constraint<Graph>(
                        uint2(root_kind == 9u ? 1u : 2u, dependency_type_word(root * 9u + 1u)),
                        root_kind == 8u ? dependency_generic_const_slot(root) : INVALID, instance,
                        uint2(kind, value), tokens, infer_constants, constants, constant_mask, false)) return false;
                expected = pair.yz;
            }
            else if (root_kind == 2u)
            {
                uint slot = dependency_generic_type_slot(root);
                if (!Graph.environment_argument(instance, slot, expected.x, expected.y))
                {
                    // Result annotations are constraints on otherwise free
                    // parameters. Repeated occurrences must agree by complete
                    // checked identity, even when they have equal layouts.
                    if (!infer_unbound || slot >= 32u) return false;
                    uint bit = 1u << slot;
                    if ((inferred_mask & bit) == 0u)
                    {
                        inferred[slot] = pair.yz;
                        inferred_mask |= bit;
                    }
                    expected = inferred[slot];
                }
            }
            if (!canonical_field_leaf<Graph>(instance, expected)) return false;
            next[depth] = 0u; counts[depth] = 0u;
            if (expected.x != 5u)
            {
                if (!scoped_type_refs_equal<Graph>(expected.x, expected.y, INVALID,
                    pair.y, pair.z, INVALID, capacity, tokens)) return false;
            }
            else
            {
                pair.x = expected.y; pairs[depth] = pair;
                if (pair.y != 3u || pair.z >= capacity) return false;
                uint kind = dependency_type_word(pair.x * 9u) - 2u;
                uint actual_kind = Graph.metadata(pair.z, 0u);
                bool slice_coercion = allow_root_array_to_slice && depth == 0u && kind == 3u && actual_kind == 2u;
                if (kind != actual_kind && !slice_coercion) return false;
                if (kind == 1u)
                {
                    if (Graph.metadata(pair.z, 1u) != INVALID ||
                        dependency_type_word(pair.x * 9u + 1u) != Graph.metadata(pair.z, 7u) ||
                        dependency_type_word(pair.x * 9u + 8u) != Graph.metadata(pair.z, 8u) ||
                        dependency_type_word(pair.x * 9u + 2u) != Graph.metadata(pair.z, 9u)) return false;
                    counts[depth] = dependency_type_word(pair.x * 9u + 4u);
                    if (counts[depth] != Graph.metadata(pair.z, 2u)) return false;
                }
                else
                {
                    if (kind == 2u)
                    {
                        uint2 length = uint2(dependency_type_word(pair.x * 9u + 5u), dependency_type_word(pair.x * 9u + 6u));
                        uint slot = length.x == 2u ? dependency_generic_const_slot(pair.x) : INVALID;
                        if (!constant_reference_constraint<Graph>(length, slot, instance,
                            uint2(Graph.metadata(pair.z, 5u), Graph.metadata(pair.z, 6u)),
                            tokens, infer_constants, constants, constant_mask, false)) return false;
                    }
                    counts[depth] = 1u;
                }
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return true;
            depth--; continue;
        }
        uint slot = next[depth]++;
        uint tag; uint payload;
        if (Graph.metadata(pair.z, 0u) == 1u)
        {
            if (!Graph.argument(pair.z, slot, tag, payload)) return false;
        }
        else { tag = Graph.metadata(pair.z, 3u); payload = Graph.metadata(pair.z, 4u); }
        uint child = dependency_type_edge_word(dependency_type_word(pair.x * 9u + 3u) + slot);
        if (depth + 1u == LIMIT) return false;
        depth++; pairs[depth] = uint3(child, tag, payload); next[depth] = INVALID;
    }
}

public bool canonical_type_ref_constraints<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint actual_tag, uint actual_payload, uint capacity, uint tokens, bool infer_unbound,
    out uint2 inferred[32], out uint inferred_mask, bool allow_root_array_to_slice = false)
{
    uint2 constants[32]; uint constant_mask;
    return canonical_type_and_constant_constraints<Graph>(instance, type, actual_tag, actual_payload,
        capacity, tokens, infer_unbound, inferred, inferred_mask, constants, constant_mask,
        false, allow_root_array_to_slice);
}

public bool canonical_field_ref_constraints<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint candidate, uint capacity, uint tokens, bool infer_unbound,
    out uint2 inferred[32], out uint inferred_mask, bool allow_root_array_to_slice = false)
{
    return canonical_type_ref_constraints<Graph>(instance, type, 3u, candidate,
        capacity, tokens, infer_unbound, inferred, inferred_mask, allow_root_array_to_slice);
}

// Exact comparison consumes existing bindings and never infers new ones.
// Keep its traversal independent of the constraint producer's output arrays.
public bool canonical_field_ref_matches<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint candidate, uint capacity, uint tokens)
{
    static const uint INVALID = 0xffffffffu;
    static const uint LIMIT = 64u;
    uint3 pairs[LIMIT]; uint next[LIMIT]; uint counts[LIMIT];
    uint depth = 0u;
    pairs[0u] = uint3(type, 3u, candidate); next[0u] = INVALID;
    for (;;)
    {
        uint3 pair = pairs[depth];
        if (next[depth] == INVALID)
        {
            uint2 expected = uint2(5u, pair.x);
            if (!canonical_field_leaf<Graph>(instance, expected)) return false;
            next[depth] = 0u; counts[depth] = 0u;
            if (application_argument_is_constant(expected.x))
            {
                uint2 left; uint2 right;
                if (!application_constant_argument(expected.x, expected.y, left.x, left.y) ||
                    !application_constant_argument(pair.y, pair.z, right.x, right.y) ||
                    !checked_constant_reference<Graph>(left, tokens) ||
                    !checked_constant_reference<Graph>(right, tokens) || any(left != right)) return false;
            }
            else if (expected.x != 5u)
            {
                if (!scoped_type_refs_equal<Graph>(expected.x, expected.y, INVALID,
                    pair.y, pair.z, INVALID, capacity, tokens)) return false;
            }
            else
            {
                pair.x = expected.y; pairs[depth] = pair;
                if (pair.y != 3u || pair.z >= capacity) return false;
                uint kind = dependency_type_word(pair.x * 9u) - 2u;
                if (kind < 1u || kind > 4u || kind != Graph.metadata(pair.z, 0u)) return false;
                if (kind == 1u)
                {
                    if (Graph.metadata(pair.z, 1u) != INVALID ||
                        dependency_type_word(pair.x * 9u + 1u) != Graph.metadata(pair.z, 7u) ||
                        dependency_type_word(pair.x * 9u + 8u) != Graph.metadata(pair.z, 8u) ||
                        dependency_type_word(pair.x * 9u + 2u) != Graph.metadata(pair.z, 9u)) return false;
                    counts[depth] = dependency_type_word(pair.x * 9u + 4u);
                    if (counts[depth] > 32u || counts[depth] != Graph.metadata(pair.z, 2u)) return false;
                }
                else
                {
                    if (kind == 2u)
                    {
                        uint2 length = uint2(dependency_type_word(pair.x * 9u + 5u),
                            dependency_type_word(pair.x * 9u + 6u));
                        uint2 actual = uint2(Graph.metadata(pair.z, 5u), Graph.metadata(pair.z, 6u));
                        if (!canonical_constant_length<Graph>(instance, pair.x, length.x, length.y) ||
                            !checked_constant_reference<Graph>(length, tokens) ||
                            !checked_constant_reference<Graph>(actual, tokens) || any(length != actual)) return false;
                    }
                    counts[depth] = 1u;
                }
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return true;
            depth--; continue;
        }
        uint ordinal = next[depth]++;
        uint tag; uint payload;
        if (Graph.metadata(pair.z, 0u) == 1u)
        {
            if (!Graph.argument(pair.z, ordinal, tag, payload)) return false;
        }
        else { tag = Graph.metadata(pair.z, 3u); payload = Graph.metadata(pair.z, 4u); }
        uint child = dependency_type_edge_word(dependency_type_word(pair.x * 9u + 3u) + ordinal);
        if (depth + 1u == LIMIT) return false;
        depth++; pairs[depth] = uint3(child, tag, payload); next[depth] = INVALID;
    }
}

// Resolve an already validated canonical pattern through the immutable checked
// application index. A hash selects candidates; full scoped equality decides.
public uint canonical_indexed_application<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint hash, uint capacity, uint tokens,
    StructuredBuffer<uint> lookup_head, StructuredBuffer<uint> lookup_next)
{
    static const uint INVALID = 0xffffffffu;
    uint buckets; uint stride;
    lookup_head.GetDimensions(buckets, stride);
    if (buckets == 0u) return INVALID;
    uint link = lookup_head[hash % buckets];
    for (uint steps = 0u; steps < capacity && link != 0u; steps++)
    {
        uint candidate = link - 1u;
        if (candidate >= capacity) return INVALID;
        if (canonical_field_ref_matches<Graph>(instance, type, candidate, capacity, tokens))
            return candidate;
        link = lookup_next[candidate];
    }
    return INVALID;
}

// Publish only caller-side checked references. Layout and field consumers use
// the same relation as application producers, without retaining page-local IDs.
public bool canonical_checked_reference<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint capacity, uint tokens,
    StructuredBuffer<uint> lookup_head, StructuredBuffer<uint> lookup_next,
    out uint2 reference)
{
    reference = uint2(5u, type);
    if (!canonical_field_leaf<Graph>(instance, reference)) return false;
    if (reference.x != 5u) return true;
    uint hash;
    if (!canonical_field_ref_hash<Graph>(instance, reference.y, capacity, tokens, hash)) return false;
    uint candidate = canonical_indexed_application<Graph>(instance, reference.y,
        hash, capacity, tokens, lookup_head, lookup_next);
    if (candidate == 0xffffffffu) return false;
    reference = uint2(3u, candidate);
    return true;
}
