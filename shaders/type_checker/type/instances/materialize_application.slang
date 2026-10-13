import type_checker.constant_materialization;
import type_checker.checked_array_counts;
// Source normalization and ordinary substitution share the traversal and
// operand contracts. Select the source-normalization policy at shader compile
// time; ordinary inference kernels must not carry alias stacks or branches.
#ifndef MATERIALIZE_NORMALIZE_ALIASES
#define MATERIALIZE_NORMALIZE_ALIASES 0
#endif
#include "allocate_application.slang"
// Shared GPU materialization under record or call parameter environments.
// The including pass owns immutable source inputs and private output rows.
uint indexed_application<Graph : IScopedTypeGraph>(uint3 reference)
{
    uint hash;
    uint capacity = mutable_type_capacity();
    if (!scoped_type_ref_hash<Graph>(reference.x, reference.y,
        reference.z, capacity, gParams.n_tokens, hash)) return INVALID;
    uint buckets; uint stride;
    type_instance_lookup_head.GetDimensions(buckets, stride);
    uint link = type_instance_lookup_head[hash % buckets];
    for (uint steps = 0u; steps < capacity && link != 0u; steps++)
    {
        uint candidate = link - 1u;
        if (candidate >= capacity) return INVALID;
        if (scoped_type_refs_equal<Graph>(reference.x, reference.y,
            reference.z, 3u, candidate, INVALID, capacity, gParams.n_tokens)) return candidate;
        link = type_instance_lookup_next[candidate];
    }
    return INVALID;
}

bool materialize_source_constant<Graph : IScopedTypeGraph>(uint environment,
    inout uint kind, inout uint payload, out uint failure)
{
    uint2 result;
    if (!materialize_checked_constant<Graph, ScopedConstantEnvironment<Graph>>(
        uint3(kind, payload, environment), gParams.n_tokens, result, failure)) return false;
    kind = result.x; payload = result.y; return true;
}

#if !MATERIALIZE_NORMALIZE_ALIASES
bool materialize_canonical_constant<Graph : IScopedTypeGraph>(uint environment,
    uint canonical, out uint kind, out uint payload, out uint failure)
{
    kind = 0u; payload = INVALID; failure = 4u;
    uint parameters; uint projections; uint tokens; uint2 input; uint2 result;
    if (!canonical_constant_view_ranges(parameters, projections, tokens) ||
        !canonical_constant_view_reference<Graph>(canonical, input) ||
        !materialize_checked_constant<CanonicalConstantGraph<Graph>, CanonicalConstantEnvironment<Graph>>(
            uint3(input, environment), tokens, result, failure)) return false;
    kind = result.x; payload = result.y; return true;
}
#endif

#if MATERIALIZE_NORMALIZE_ALIASES
// Aliases retain their immediate target and their own parameter environment.
// Expanding a flattened target under a different alias's slots captures the
// wrong parameters when headers reorder, omit, or inject arguments.
uint alias_target_node(uint instance)
{
    uint declaration = type_instance_decl_token[instance];
    uint owner = declaration < gParams.n_tokens ? type_decl_hir_node_by_token[declaration] : INVALID;
    return owner < hir_count() && compact_hir_payload[owner].a == 8u
        ? compact_type_alias_target[owner] : INVALID;
}

uint allocate_normalized_application<Graph : IScopedTypeGraph>(uint3 ref, uint reuse, uint2 prepared_length, out uint failure)
{
    failure = 0u;
    uint source = ref.y;
    uint kind = type_instance_kind[source];
    uint length_kind = type_instance_len_kind[source];
    uint length = type_instance_len_payload[source];
    if (kind == 2u)
    {
        if (prepared_length.x != 0u) { length_kind = prepared_length.x; length = prepared_length.y; }
        else if (!materialize_source_constant<Graph>(ref.z, length_kind, length, failure)) return INVALID;
        if (!checked_source_array_length_valid(length_kind, length, gParams.n_tokens))
            { failure = 3u; return INVALID; }
    }
    uint target = reuse;
    if (target == INVALID)
        target = allocate_application(type_instance_decl_token[source], type_instance_arg_count[source],
            length_kind, length, external_type_library_id[source], external_type_unit_id[source],
            external_type_local_index[source]);
    else
    {
        // Tail expansion alternates private alias environments. All arguments
        // are caller-side checked references before this row becomes an
        // environment; the preceding environment stays immutable while its
        // reordered arguments are being evaluated.
        type_instance_kind[target] = 0u;
        type_instance_decl_token[target] = type_instance_decl_token[source];
        type_instance_arg_count[target] = type_instance_arg_count[source];
        type_instance_len_kind[target] = length_kind;
        type_instance_len_payload[target] = length;
        external_type_library_id[target] = external_type_library_id[source];
        external_type_unit_id[target] = external_type_unit_id[source];
        external_type_local_index[target] = external_type_local_index[source];
    }
    if (target == INVALID) failure = 1u;
    return target;
}

#endif

// This lane can reuse its completed nodes immediately. Other lanes see the
// immutable source index; duplicate complete nodes are safe and compare by
// their entire structure, rather than allocation order or native width.
bool materialize<Graph : IScopedTypeGraph>(uint3 input, inout uint created[DEPTH_LIMIT], inout uint created_count,
    out uint2 result, out uint failure)
{
    uint3 refs[DEPTH_LIMIT];
    uint targets[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint counts[DEPTH_LIMIT];
    uint kinds[DEPTH_LIMIT];
#if MATERIALIZE_NORMALIZE_ALIASES
    uint alias_environment_a[DEPTH_LIMIT]; uint alias_environment_b[DEPTH_LIMIT];
        for (uint i = 0u; i < DEPTH_LIMIT; i++)
            { alias_environment_a[i] = INVALID; alias_environment_b[i] = INVALID; }
    uint alias_expansions = 0u;
#endif
    uint depth = 0u;
    refs[0u] = input; next[0u] = INVALID;
    result = uint2(0u, INVALID); failure = 0u;
    for (;;)
    {
        uint3 ref = refs[depth];
        bool complete = false;
        uint2 value = uint2(0u, INVALID);
        if (next[depth] == INVALID)
        {
#if MATERIALIZE_NORMALIZE_ALIASES
            uint alias_capacity; uint alias_stride;
            imported_type_alias_target.GetDimensions(alias_capacity, alias_stride);
            if (ref.x == 3u && ref.y < alias_capacity)
            {
                uint2 expanded = imported_type_alias_target[ref.y];
                if (expanded.x != 0u && expanded.y != INVALID)
                {
                    if (alias_expansions++ >= gParams.n_hir_nodes) { failure = 5u; return false; }
                    // The retained target is expressed in the caller's lexical
                    // parameters. Keep the surrounding substitution environment
                    // when expanding it inside another local/imported alias.
                    refs[depth] = uint3(expanded, ref.z);
                    continue;
                }
            }
#endif
#if !MATERIALIZE_NORMALIZE_ALIASES
            if (ref.x == 5u)
            {
                uint portable_kind = dependency_type_word(ref.y * 9u);
                if (portable_kind == 8u || portable_kind == 9u || portable_kind == 10u)
                {
                    uint constant_kind; uint constant_payload;
                    if (!materialize_canonical_constant<Graph>(ref.z, ref.y,
                        constant_kind, constant_payload, failure)) return false;
                    ref = uint3(APPLICATION_CONSTANT_ARGUMENT | constant_kind, constant_payload, INVALID);
                }
                uint2 canonical = ref.xy;
                if (ref.x == 5u && !canonical_field_leaf<Graph>(ref.z, canonical))
                    { failure = 4u; return false; }
                ref = uint3(canonical, canonical.x == 5u ? ref.z : INVALID);
            }
#endif
            if (ref.x == 2u && ref.z != INVALID)
            {
                uint slot = ref.y < gParams.n_tokens ? type_generic_param_slot_by_token[ref.y] : INVALID;
                uint tag; uint payload;
                if (slot == INVALID || !Graph.environment_argument(ref.z, slot, tag, payload))
                    { failure = 3u; return false; }
                ref = uint3(tag, payload, INVALID);
            }
            if (application_argument_is_constant(ref.x))
            {
                uint kind = ref.x & ~APPLICATION_CONSTANT_ARGUMENT;
                if (!materialize_source_constant<Graph>(ref.z, kind, ref.y, failure))
                    return false;
                ref.x = APPLICATION_CONSTANT_ARGUMENT | kind; ref.z = INVALID;
            }
            refs[depth] = ref;
            if (application_argument_is_constant(ref.x))
            { value = ref.xy; complete = true; }
            else if ((ref.x == 1u && ref.y != 0u && ref.y != INVALID) ||
                (ref.x == 2u && ref.y < gParams.n_tokens &&
                 type_generic_param_slot_by_token[ref.y] != INVALID))
            {
                value = ref.xy; complete = true;
            }
#if MATERIALIZE_NORMALIZE_ALIASES
            else if (ref.x == 3u && ref.y < mutable_type_capacity())
            {
                uint kind = type_instance_kind[ref.y];
                uint arguments = kind == 1u ? type_instance_arg_count[ref.y] : 1u;
                if (kind < 1u || kind > 4u || arguments > ARG_LIMIT) { failure = 2u; return false; }
                kinds[depth] = kind; counts[depth] = arguments;
                targets[depth] = INVALID; next[depth] = 0u;
                if (kind == 2u)
                {
                    uint length_kind = type_instance_len_kind[ref.y];
                    uint length = type_instance_len_payload[ref.y];
                    if (!materialize_source_constant<Graph>(ref.z, length_kind, length, failure))
                        return false;
                    if (length_kind != type_instance_len_kind[ref.y] || length != type_instance_len_payload[ref.y])
                    {
                        targets[depth] = allocate_normalized_application<Graph>(ref, INVALID, uint2(length_kind, length), failure);
                        if (targets[depth] == INVALID) return false;
                    }
                }
            }
#else
            else if (ref.x == 3u && ref.z == INVALID && ref.y < mutable_type_capacity())
            {
                // Substitution has already produced a caller-side reference.
                // Validate its complete graph, then retain it directly. Looking
                // it up again can compare the same tree repeatedly or allocate
                // a duplicate before the next index publication.
                uint hash;
                if (!scoped_type_ref_hash<Graph>(ref.x, ref.y, INVALID,
                    mutable_type_capacity(), gParams.n_tokens, hash))
                    { failure = 3u; return false; }
                value = ref.xy; complete = true;
            }
            else if ((ref.x == 3u && ref.y < mutable_type_capacity()) || ref.x == 5u)
            {
                uint found = INVALID;
                if (ref.x == 3u)
                {
                    found = indexed_application<Graph>(ref);
                    for (uint i = 0u; found == INVALID && i < created_count; i++)
                        if (scoped_type_refs_equal<Graph>(ref.x, ref.y, ref.z,
                            3u, created[i], INVALID, mutable_type_capacity(), gParams.n_tokens)) found = created[i];
                }
                else
                {
                    uint hash;
                    if (!canonical_field_ref_hash<Graph>(ref.z, ref.y,
                        mutable_type_capacity(), gParams.n_tokens, hash)) { failure = 4u; return false; }
                    found = canonical_indexed_application<Graph>(ref.z, ref.y, hash,
                        mutable_type_capacity(), gParams.n_tokens,
                        type_instance_lookup_head, type_instance_lookup_next);
                    for (uint i = 0u; found == INVALID && i < created_count; i++)
                        if (canonical_field_ref_matches<Graph>(ref.z, ref.y, created[i],
                            mutable_type_capacity(), gParams.n_tokens)) found = created[i];
                }
                if (found != INVALID)
                {
                    value = uint2(3u, found); complete = true;
                }
                else
                {
                    uint hash;
                    if (ref.x == 3u && !scoped_type_ref_hash<Graph>(ref.x, ref.y, ref.z,
                        mutable_type_capacity(), gParams.n_tokens, hash)) { failure = 3u; return false; }
                    uint kind = ref.x == 5u ? dependency_type_word(ref.y * 9u) - 2u : type_instance_kind[ref.y];
                    uint arguments = kind == 1u ? (ref.x == 5u
                        ? dependency_type_word(ref.y * 9u + 4u) : type_instance_arg_count[ref.y]) : 0u;
                    if (arguments > ARG_LIMIT) { failure = 2u; return false; }
                    uint2 domains = ref.x == 5u && kind == 1u ? canonical_application_domains(ref.y) : uint2(0u, 0u);
                    uint length_kind = ref.x == 5u
                        ? (kind == 1u ? domains.x : 0u)
                        : type_instance_len_kind[ref.y];
                    uint length = ref.x == 5u
                        ? (kind == 1u ? domains.y : INVALID)
                        : type_instance_len_payload[ref.y];
                    if (kind == 2u)
                    {
                        bool resolved = ref.x == 5u
                            ? materialize_canonical_constant<Graph>(ref.z, dependency_array_length_type(ref.y),
                                length_kind, length, failure)
                            : materialize_source_constant<Graph>(ref.z, length_kind, length, failure);
                        if (!resolved) return false;
                        if (!checked_source_array_length_valid(length_kind, length, gParams.n_tokens))
                            { failure = 3u; return false; }
                    }
                    uint target = allocate_application(
                        ref.x == 5u ? INVALID : type_instance_decl_token[ref.y], arguments,
                        length_kind, length,
                        ref.x == 5u ? (kind == 1u ? dependency_type_word(ref.y * 9u + 1u) : INVALID) : external_type_library_id[ref.y],
                        ref.x == 5u ? (kind == 1u ? dependency_type_word(ref.y * 9u + 8u) : INVALID) : external_type_unit_id[ref.y],
                        ref.x == 5u ? (kind == 1u ? dependency_type_word(ref.y * 9u + 2u) : INVALID) : external_type_local_index[ref.y]);
                    if (target == INVALID) { failure = 1u; return false; }
                    targets[depth] = target; next[depth] = 0u;
                    kinds[depth] = kind;
                    counts[depth] = kind == 1u ? arguments : 1u;
                }
            }
            #endif
            else { failure = 3u; return false; }
        }
        if (!complete && next[depth] == counts[depth])
        {
#if MATERIALIZE_NORMALIZE_ALIASES
            uint target = targets[depth];
            if (target != INVALID) type_instance_kind[target] = kinds[depth];
            value = uint2(3u, target == INVALID ? ref.y : target);
#if MATERIALIZE_NORMALIZE_ALIASES
            uint alias_target = kinds[depth] == 1u ? alias_target_node(value.y) : INVALID;
            if (alias_target < hir_count())
            {
                // Acyclic declaration chains have at most one expansion per
                // declaration along this path. The input-sized bound also
                // terminates recursive aliases without a fixed alias-hop cap.
                if (alias_expansions++ >= gParams.n_hir_nodes) { failure = 5u; return false; }
                uint token = type_token(alias_target);
                if (token >= gParams.n_tokens) { failure = 3u; return false; }
                refs[depth] = uint3(type_expr_ref_tag[token], type_expr_ref_payload[token], value.y);
                next[depth] = INVALID;
                continue;
            }
#endif
            if (target != INVALID)
            {
                if (created_count == DEPTH_LIMIT) { failure = 2u; return false; }
                created[created_count++] = target;
            }
            complete = true;
#else
            uint target = targets[depth];
            type_instance_kind[target] = kinds[depth];
            if (created_count == DEPTH_LIMIT) { failure = 2u; return false; }
            created[created_count++] = target;
            value = uint2(3u, target); complete = true;
#endif
        }
        if (complete)
        {
#if MATERIALIZE_NORMALIZE_ALIASES
            if (depth == 0u)
            {
#if MATERIALIZE_NORMALIZE_ALIASES
                    for (uint i = 0u; i < DEPTH_LIMIT; i++)
                    {
                        if (alias_environment_a[i] != INVALID) type_instance_kind[alias_environment_a[i]] = 0u;
                        if (alias_environment_b[i] != INVALID) type_instance_kind[alias_environment_b[i]] = 0u;
                    }
#endif
                result = value; return true;
            }
#else
            if (depth == 0u) { result = value; return true; }
#endif
            depth--;
            uint parent = targets[depth];
            uint slot = next[depth] - 1u;
#if MATERIALIZE_NORMALIZE_ALIASES
            if (refs[depth].x == 3u && parent == INVALID)
            {
                uint source = refs[depth].y;
                uint old_tag; uint old_payload;
                if (kinds[depth] == 1u)
                {
                    if (!Graph.argument(source, slot, old_tag, old_payload)) { failure = 3u; return false; }
                }
                else { old_tag = type_instance_elem_ref_tag[source]; old_payload = type_instance_elem_ref_payload[source]; }
                if (all(value == uint2(old_tag, old_payload))) continue;
                bool alias = kinds[depth] == 1u && alias_target_node(source) < hir_count();
                bool use_a = refs[depth].z != alias_environment_a[depth];
                uint reuse = alias ? (use_a ? alias_environment_a[depth] : alias_environment_b[depth]) : INVALID;
                parent = allocate_normalized_application<Graph>(refs[depth], reuse, uint2(0u, INVALID), failure);
                if (parent == INVALID) return false;
                targets[depth] = parent;
                if (alias)
                {
                    if (use_a) alias_environment_a[depth] = parent;
                    else alias_environment_b[depth] = parent;
                }
                // Earlier children are unchanged. Copy them once when the
                // first changed edge makes a new complete node necessary.
                if (kinds[depth] == 1u)
                    for (uint i = 0u; i < slot; i++)
                    {
                        uint tag; uint payload;
                        if (!Graph.argument(source, i, tag, payload)) { failure = 3u; return false; }
                        uint edge = type_instance_arg_start[parent] + i;
                        type_instance_arg_ref_tag[edge] = tag; type_instance_arg_ref_payload[edge] = payload;
                    }
            }
#endif
            if (kinds[depth] == 1u)
            {
                uint start = type_instance_arg_start[parent];
                type_instance_arg_ref_tag[start + slot] = value.x;
                type_instance_arg_ref_payload[start + slot] = value.y;
            }
            else
            {
                type_instance_elem_ref_tag[parent] = value.x;
                type_instance_elem_ref_payload[parent] = value.y;
            }
            continue;
        }
        uint slot = next[depth]; next[depth] = slot + 1u;
        uint tag; uint payload;
        if (ref.x == 5u)
        {
            tag = 5u;
            payload = dependency_type_edge_word(dependency_type_word(ref.y * 9u + 3u) + slot);
        }
        else if (type_instance_kind[ref.y] == 1u)
        {
            if (!Graph.argument(ref.y, slot, tag, payload))
                { failure = 3u; return false; }
        }
        else { tag = type_instance_elem_ref_tag[ref.y]; payload = type_instance_elem_ref_payload[ref.y]; }
        if (depth + 1u == DEPTH_LIMIT) { failure = 2u; return false; }
        depth++; refs[depth] = uint3(tag, payload, ref.z); next[depth] = INVALID;
    }
}
