import type_checker.checked_array_counts;
import type_checker.constant_publication;
// Array syntax owns its dimensions independently of its element type. Use
// those dimensions only to produce optional literal context when a declared
// constant length is not bound yet. Complete argument matching still checks
// the original parameter pattern and publishes the accepted call bindings.
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;

bool array_context_child(uint2 pattern, out uint2 child)
{
    child = uint2(0u, INVALID);
    if (pattern.x == 3u && pattern.y < mutable_type_capacity() &&
        type_instance_kind[pattern.y] == 2u)
    {
        child = uint2(type_instance_elem_ref_tag[pattern.y], type_instance_elem_ref_payload[pattern.y]);
        return child.x != 0u && child.y != INVALID;
    }
    if (pattern.x != 5u) return false;
    uint root = canonical_field_root(pattern.y);
    if (root == INVALID || dependency_type_word(root * 9u) != 4u ||
        dependency_type_word(root * 9u + 4u) != 1u) return false;
    uint start = dependency_type_word(root * 9u + 3u);
    if (start >= dependency_count(5u)) return false;
    child = uint2(5u, dependency_type_edge_word(start));
    return child.y < dependency_type_count();
}

bool prepare_array_shape_context(uint3 pattern, uint literal, uint prior,
    out uint3 leaf, out uint length_atoms[DEPTH_LIMIT], out uint previous[DEPTH_LIMIT],
    out uint depth, out uint failure)
{
    depth = 0u;
    leaf = pattern; failure = 3u;
    uint2 child;
    for (;;)
    {
        if (literal >= hir_count() || compact_hir_core[literal].kind != 24u ||
            !array_context_child(pattern.xy, child)) return false;
        if (depth == DEPTH_LIMIT) { failure = 2u; return false; }
        uint length = compact_array_element_count[literal];
        uint atom_row = gParams.n_hir_nodes + literal;
        uint2 length_reference;
        if (atom_row < gParams.n_hir_nodes ||
            !publish_checked_constant_atom_at(atom_row, uint3(SCALAR_U32, length, 0u), length_reference))
        { failure = 1u; return false; }
        length_atoms[depth] = length_reference.y;
        previous[depth] = prior < mutable_type_capacity() &&
            type_instance_kind[prior] == 2u &&
            checked_source_array_length_matches_count(type_instance_len_kind[prior],
                type_instance_len_payload[prior], length, gParams.n_tokens) ? prior : INVALID;
        prior = previous[depth] != INVALID && type_instance_elem_ref_tag[prior] == 3u
            ? type_instance_elem_ref_payload[prior] : INVALID;
        depth++;
        uint first = compact_array_element_start[literal];
        uint nested = length != 0u && first < min(compact_array_element_row_count[0u], gParams.n_hir_nodes)
            ? argument_context_root(compact_array_elements[first].value, hir_count(),
                compact_hir_core, compact_hir_payload) : INVALID;
        uint2 next_child;
        if (nested < hir_count() && compact_hir_core[nested].kind == 24u &&
            array_context_child(child, next_child))
        {
            pattern.xy = child; literal = nested;
            continue;
        }
        // An empty outer array provides no evidence for an unbound inner
        // dimension or element parameter. Materialization must still resolve
        // that complete child from the accepted environment.
        leaf = uint3(child, pattern.z);
        failure = 0u;
        return true;
    }
}

bool wrap_array_shape_context<Graph : IScopedTypeGraph>(uint depth,
    uint length_atoms[DEPTH_LIMIT], uint previous[DEPTH_LIMIT],
    inout uint2 result, out uint failure)
{
    failure = 0u;
    while (depth != 0u)
    {
        depth--;
        uint target = previous[depth];
        if (target != INVALID && scoped_type_refs_equal<Graph>(
            type_instance_elem_ref_tag[target], type_instance_elem_ref_payload[target], INVALID,
            result.x, result.y, INVALID, mutable_type_capacity(), gParams.n_tokens))
        {
            result = uint2(3u, target);
            continue;
        }
        target = allocate_application(INVALID, 0u, 1u, length_atoms[depth], INVALID, INVALID, INVALID);
        if (target == INVALID) { failure = 1u; return false; }
        type_instance_elem_ref_tag[target] = result.x;
        type_instance_elem_ref_payload[target] = result.y;
        type_instance_kind[target] = 2u;
        result = uint2(3u, target);
    }
    failure = 0u;
    return true;
}
