import primitive_types;
import constant_value;
import type_checker.concrete_type_equality;
// Resolve declaration-side interface trees under a checked receiver. Canonical
// row numbers stay on the active page; completed applications use stable
// checked references. Hashes select buckets only, never establish equality.
import dependency_interface;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;
import type_checker.constant_constraints;
import type_checker.dependencies.constant_view;

public StructuredBuffer<uint> canonical_type_roots;

public uint canonical_field_root(uint type)
{
    uint count = dependency_type_count();
    uint root = type < count ? canonical_type_roots[type] : 0xffffffffu;
    return root < count ? root : 0xffffffffu;
}

// Imported headers keep their exact member/type identity. Only the inferred
// value is a caller-owned source reference; array counts use a separate fit API.
public bool canonical_constant_constraint<Graph : IScopedTypeGraph>(uint environment,
    uint type, uint2 actual, uint tokens, bool infer_unbound,
    inout InferredConstant inferred[32], inout uint mask, bool count_identity)
{
    if (type >= dependency_type_count()) return false;
    uint root_kind = dependency_type_word(type * 9u);
    bool concrete = false;
    uint count = 0u;
    uint2 source = actual;
    // Only a projected pattern inspects the source before terminal admission.
    // Direct parameters and other root kinds retain their original validators.
    if (root_kind == 10u)
    {
        InferredConstantDescriptor candidate;
        if (!inferred_constant_request_descriptor<Graph>(inferred_constant_reference(actual),
            tokens, candidate) || !scalar_is_integer(candidate.result_scalar)) return false;
        uint root_scalar = dependency_constant_scalar(type);
        if (!count_identity && candidate.result_scalar != root_scalar) return false;
        concrete = candidate.source.disposition == CONSTANT_REFERENCE_CONCRETE;
        if (concrete && !constant_value_to_count(candidate.value, count)) return false;
    }
    uint current = type;
    // Direct and projected terminals share one call site per constraint helper.
    // Keep the original visit limit: a terminal after 64 projection edges is not
    // visited, so the chain still rejects without changing inferred outputs.
    [loop]
    for (uint work = 0u; work < CONSTANT_REFERENCE_WORK_LIMIT; work++)
    {
        uint kind = work == 0u ? root_kind : dependency_type_word(current * 9u);
        if (kind == 8u)
        {
            uint scalar = dependency_const_parameter_scalar(current);
            uint slot = dependency_generic_const_slot(current);
            // The expected recipe remains intact. Publication binds only its
            // exact terminal member, retaining all outer fit obligations.
            return concrete || count_identity
                ? array_count_parameter_constraint<Graph>(scalar, slot, environment,
                    actual, tokens, infer_unbound, inferred, mask, count_identity ? 1u : 0u)
                : constant_parameter_constraint<Graph>(scalar, slot, environment,
                    source, tokens, infer_unbound, inferred, mask);
        }
        if (kind != 10u)
            return canonical_constant_matches<Graph>(environment, type, actual, tokens, count_identity);
        uint target; uint child;
        if (!dependency_count_projection_child(current, target, child)) return false;
        if (concrete)
        {
            uint3 converted;
            if (!constant_value_from_count(count, target, converted)) return false;
        }
        else if (!count_identity)
        {
            // Typed symbolic identity includes each projection target. Only
            // matching source-owned prefixes can be removed for inference.
            uint source_target; uint2 source_child;
            if (source.x != 3u || !Graph.constant_projection(source.y, source_target, source_child) ||
                source_target != target) return false;
            source = source_child;
        }
        current = child;
    }
    return false;
}

// A type-parameter replacement stays in the type domain. Canonical references
// are permitted; constants belong to independent ordered operands and lengths.
// This is a domain check, not recursive validation or an extra substitution.
public bool canonical_type_parameter_reference(uint2 reference)
{
    if (reference.x == 1u || reference.x == 2u || reference.x == 3u) return true;
    if (reference.x != 5u) return false;
    uint root = canonical_field_root(reference.y);
    if (root == 0xffffffffu) return false;
    uint kind = dependency_type_word(root * 9u);
    return kind >= 1u && kind <= 6u;
}

// Shared type-only resolver body. Callers choose the operand domain before
// entering it, so type traversal does not compile the constant recipe bridge.
bool canonical_type_field_leaf_at_root<Graph : IScopedTypeGraph>(uint instance,
    uint root, uint kind, inout uint2 reference)
{
    if (kind == 1u)
    {
        reference = uint2(1u, dependency_type_word(root * 9u + 1u));
        return reference.y != 0u && reference.y != 0xffffffffu;
    }
    if (kind == 2u)
        return Graph.environment_argument(instance, dependency_generic_type_slot(root), reference.x, reference.y);
    uint start = dependency_type_word(root * 9u + 3u);
    uint count = dependency_type_word(root * 9u + 4u);
    uint edges = dependency_count(5u);
    if (start > edges || count > edges - start) return false;
    if (kind == 3u) return count <= 32u;
    if (kind == 4u)
        return count == 2u && dependency_array_length_type(root) != 0xffffffffu;
    // Slices and references each own one complete child type. Their distinct
    // node kinds retain value/borrow semantics through hashing and replay.
    return (kind == 5u || kind == 6u) && count == 1u;
}

// Constants have their own constraint/hash/match branches. A parameter may
// return a canonical type reference in one step; do not recursively substitute it.
public bool canonical_type_field_leaf<Graph : IScopedTypeGraph>(uint instance,
    inout uint2 reference)
{
    if (reference.x != 5u) return true;
    uint root = canonical_field_root(reference.y);
    if (root == 0xffffffffu) return false;
    reference.y = root;
    uint kind = dependency_type_word(root * 9u);
    if (kind == 8u || kind == 9u || kind == 10u) return false;
    if (!canonical_type_field_leaf_at_root<Graph>(instance, root, kind, reference)) return false;
    return kind != 2u || canonical_type_parameter_reference(reference);
}

// General leaf resolution remains available to materialization and complete
// reference consumers that have not yet classified their operand domain.
public bool canonical_field_leaf<Graph : IScopedTypeGraph>(uint instance, inout uint2 reference)
{
    if (reference.x != 5u) return true;
    uint root = canonical_field_root(reference.y);
    if (root == 0xffffffffu) return false;
    reference.y = root;
    uint kind = dependency_type_word(root * 9u);
    if (kind == 8u || kind == 9u || kind == 10u)
    {
        uint parameters; uint projections; uint limit; uint2 source;
        if (!canonical_constant_view_ranges(parameters, projections, limit)) return false;
        if (canonical_constant_source_reference<Graph>(instance, root, parameters, source))
        {
            reference = uint2(APPLICATION_CONSTANT_ARGUMENT | source.x, source.y);
            return true;
        }
        // A projection with imported parameters is a recipe until the checked
        // materializer binds the environment and publishes source-owned rows.
        uint scalar; uint child;
        return kind == 10u && dependency_count_projection_child(root, scalar, child);
    }
    return canonical_type_field_leaf_at_root<Graph>(instance, root, kind, reference);
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
        if (kind == 8u || kind == 9u || kind == 10u) { saw_constant = true; constants |= 1u << ordinal; }
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
            uint constant_type = ref.x == 5u ? canonical_field_root(ref.y) : INVALID;
            uint portable_kind = constant_type < dependency_type_count()
                ? dependency_type_word(constant_type * 9u) : 0u;
            bool canonical_constant = portable_kind == 8u || portable_kind == 9u || portable_kind == 10u;
            if (!canonical_constant && !canonical_type_field_leaf<Graph>(instance, ref)) return false;
            refs[depth] = ref; next[depth] = 0u; counts[depth] = 0u;
            hash = scoped_type_hash_mix(hash, canonical_constant || application_argument_is_constant(ref.x)
                ? APPLICATION_CONSTANT_ARGUMENT : ref.x == 5u ? 3u : ref.x);
            if (canonical_constant || application_argument_is_constant(ref.x))
            {
                uint identity_hash;
                bool valid = canonical_constant
                    ? canonical_constant_hash<Graph>(instance, constant_type, false, identity_hash)
                    : scoped_constant_ref_hash<Graph>(uint3(ref.x & ~APPLICATION_CONSTANT_ARGUMENT,
                        ref.y, INVALID), tokens, identity_hash);
                if (!valid) return false;
                hash = scoped_type_hash_mix(hash, identity_hash);
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
                        uint identity_hash;
                        bool valid = ref.x == 5u
                            ? canonical_constant_hash<Graph>(instance,
                                dependency_array_length_type(ref.y), true, identity_hash)
                            : scoped_constant_count_hash<Graph>(uint3(Graph.metadata(ref.y, 5u),
                                Graph.metadata(ref.y, 6u), INVALID), tokens, identity_hash);
                        if (!valid) return false;
                        hash = scoped_type_hash_mix(hash, identity_hash);
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
    out InferredConstant constants[32], out uint constant_mask, bool infer_constants,
    bool allow_root_array_to_slice = false)
{
    static const uint INVALID = 0xffffffffu;
    static const uint LIMIT = 64u;
    uint3 pairs[LIMIT]; uint next[LIMIT]; uint counts[LIMIT];
    inferred_mask = 0u;
    constant_mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++) inferred[slot] = uint2(0u, INVALID);
    for (uint slot = 0u; slot < 32u; slot++)
    {
        constants[slot] = (InferredConstant)0;
        constants[slot].reference = uint2(0u, INVALID);
    }
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
            bool constant_pending = root_kind == 8u || root_kind == 9u || root_kind == 10u;
            bool count_identity = false;
            uint constant_type = root;
            uint2 constant_actual = uint2(0u, INVALID);
            if (constant_pending)
            {
                if (!application_constant_argument(pair.y, pair.z,
                    constant_actual.x, constant_actual.y)) return false;
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
            // A kind2 replacement can be canonical, but cannot be a constant
            // operand. Keep inferred outputs as written above on rejection.
            if (root_kind == 2u && !canonical_type_parameter_reference(expected)) return false;
            if (!constant_pending && !canonical_type_field_leaf<Graph>(instance, expected)) return false;
            next[depth] = 0u; counts[depth] = 0u;
            if (expected.x == 5u)
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
                        constant_pending = true;
                        count_identity = true;
                        constant_type = dependency_array_length_type(pair.x);
                        constant_actual = uint2(Graph.metadata(pair.z, 5u), Graph.metadata(pair.z, 6u));
                    }
                    counts[depth] = 1u;
                }
            }
            // Admit a direct operand or array count before comparing or descending.
            if (constant_pending && !canonical_constant_constraint<Graph>(instance,
                constant_type, constant_actual, tokens, infer_constants,
                constants, constant_mask, count_identity)) return false;
            if (expected.x != 5u && !scoped_type_refs_equal<Graph>(expected.x, expected.y, INVALID,
                pair.y, pair.z, INVALID, capacity, tokens)) return false;
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
    InferredConstant constants[32]; uint constant_mask;
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
    uint type, uint candidate, uint capacity, uint tokens, bool allow_root_array_to_slice = false)
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
            uint root = canonical_field_root(pair.x);
            uint root_kind = root < dependency_type_count() ? dependency_type_word(root * 9u) : 0u;
            bool constant = root_kind == 8u || root_kind == 9u || root_kind == 10u;
            if (!constant && !canonical_type_field_leaf<Graph>(instance, expected)) return false;
            next[depth] = 0u; counts[depth] = 0u;
            if (constant)
            {
                uint2 actual;
                if (!application_constant_argument(pair.y, pair.z, actual.x, actual.y) ||
                    !canonical_constant_matches<Graph>(instance, root, actual, tokens, false)) return false;
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
                uint actual_kind = Graph.metadata(pair.z, 0u);
                bool slice_borrow = allow_root_array_to_slice && depth == 0u &&
                    kind == 3u && actual_kind == 2u;
                if (kind < 1u || kind > 4u || (kind != actual_kind && !slice_borrow)) return false;
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
                        uint2 actual = uint2(Graph.metadata(pair.z, 5u), Graph.metadata(pair.z, 6u));
                        if (!canonical_constant_matches<Graph>(instance,
                            dependency_array_length_type(pair.x), actual, tokens, true)) return false;
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

// A complete signature may have a scalar or parameter at its root. Normalize
// that leaf using the same environment contract as nested leaves; compound
// roots reuse the instance comparator without widening its hot call sites.
public bool canonical_type_reference_matches<Graph : IScopedTypeGraph>(uint instance,
    uint type, uint2 candidate, uint capacity, uint tokens)
{
    uint2 expected = uint2(5u, type);
    if (!canonical_field_leaf<Graph>(instance, expected)) return false;
    if (expected.x != 5u)
        return scoped_type_refs_equal<Graph>(expected.x, expected.y, 0xffffffffu,
            candidate.x, candidate.y, 0xffffffffu, capacity, tokens);
    return candidate.x == 3u && canonical_field_ref_matches<Graph>(instance,
        expected.y, candidate.y, capacity, tokens);
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
