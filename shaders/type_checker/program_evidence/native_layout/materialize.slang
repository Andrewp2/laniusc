import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.constant_atoms;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.native_layout.recipe_abi;
import type_checker.program_evidence.native_layout.work_abi;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_term_graph;
import type_checker.scoped_type_equality;
import native_value_layout;
import primitive_types;
import type_checker.concrete_value_layout;
import type_checker.program_evidence.native_layout.work_graph;

public EvidenceStatus plm_expand_nominal(uint node, out uint first_root, out uint root_count)
{
    first_root = 0u; root_count = 0u;
    uint4 nominal; uint4 children; uint recipe; uint4 row; uint4 tail; uint4 owner; uint4 span;
    if (!plm_node(node, false, nominal, children) || nominal.x != 1u ||
        !plr_recipe_for_nominal(nominal.y, recipe))
    {
        EvidenceStatus missing = pev_invalid(175u, node, nominal.y);
        missing.state = PEV_UNSUPPORTED; return missing;
    }
    if (!plr_read_recipe(recipe, row, tail) || !pev_read_admitted_owner(row.y, owner, span) ||
        nominal.w != span.y || nominal.w > 32u) return pev_invalid(176u, node, recipe);
    // All own operands participate in admission, including phantom parameters.
    // The recipe may mention only a subset, but that cannot omit header checks.
    for (uint ordinal = 0u; ordinal < span.y; ordinal++)
    {
        uint4 parameter; uint4 atom; uint2 operand; uint domain; uint3 value;
        if (!pev_read4(3u, span.x + ordinal, 0u, parameter) ||
            parameter.x != row.y || !pev_read_admitted_parameter(parameter.y, atom) ||
            atom.y != owner.x || atom.z != parameter.w ||
            !plm_child(nominal, children, ordinal, operand, domain) ||
            (parameter.w == 0u ? !plm_type_ref(operand) :
                (operand.x != 0x80000001u || !plm_constant_value(operand.y, value) ||
                 value.x != pev_constant_parameter_scalar(parameter.y))))
            return pev_invalid(176u, node, parameter.y);
    }
    if (tail.x == 0u)
    {
        // The existing shared native evaluator has no value layout for a
        // zero-variant enum. References/slices terminate before requesting it.
        EvidenceStatus empty = pev_invalid(177u, node, recipe);
        empty.state = PEV_UNSUPPORTED; return empty;
    }
    uint first_group;
    EvidenceStatus status = plm_charge(tail.x);
    if (status.state != PEV_VALID) return status;
    status = plm_reserve(2u, tail.x, first_group);
    if (status.state != PEV_VALID) return status;
    // Derive the whole root count before writing any group. Memory limits are
    // explicit per job; no tiny body-packet node limit is reused here.
    for (uint group = 0u; group < tail.x; group++)
    {
        uint3 source;
        if (!plr_read_group(row.w + group, source) || source.x != recipe)
            return pev_invalid(178u, node, row.w + group);
        if (source.z > PEV_INVALID - 1u - root_count)
            return pev_limit(172u, 3u, PEV_INVALID, PEV_INVALID - 1u);
        root_count += source.z;
    }
    status = plm_reserve(3u, root_count, first_root);
    if (status.state != PEV_VALID) return status;
    uint root_next = first_root;
    for (uint group = 0u; group < tail.x; group++)
    {
        uint3 source;
        if (!plr_read_group(row.w + group, source) || source.x != recipe)
            return pev_invalid(178u, node, row.w + group);
        if (!plm_write2(2u, first_group + group, 0u,
            uint2(source.z == 0u ? 0u : root_next, source.z)))
            return pev_invalid(171u, 2u, first_group + group);
        for (uint ordinal = 0u; ordinal < source.z; ordinal++)
        {
            uint2 original; uint2 normalized;
            if (!pev_read_root(source.y + ordinal, original)) return pev_invalid(178u, node, source.y + ordinal);
            status = plm_copy_closed_root<SplitProofNormalizationGraphs<InputProofNormalizationGraph,
                NativeLayoutTypeGraph>, NativeLayoutRecipeBindings>(
                    original, node, row.y, normalized);
            if (status.state != PEV_VALID) return status;
            if (!plm_write2(3u, root_next++, 0u, normalized)) return pev_invalid(171u, 3u, root_next - 1u);
        }
    }
    if (root_next - first_root != root_count ||
        !plm_write4(4u, node, 0u, uint4(first_group, tail.x, first_root, PEV_INVALID)))
        return pev_invalid(178u, node, recipe);
    program_evidence_native_layout_work[15u] = first_group + tail.x;
    program_evidence_native_layout_work[16u] = first_root + root_count;
    return pev_ok();
}

// Expand only by-value edges. Nominal operand graphs retain full semantics,
// but descriptor referents do not contribute to native value layout.
public EvidenceStatus plm_expand_value_graph(uint2 root)
{
    uint2 references[PEV_DEPTH_LIMIT];
    uint next[PEV_DEPTH_LIMIT]; uint count[PEV_DEPTH_LIMIT]; uint roots[PEV_DEPTH_LIMIT];
    bool nominal[PEV_DEPTH_LIMIT];
    uint depth = 0u; references[0u] = root; next[0u] = PEV_INVALID;
    for (;;)
    {
        uint2 current = references[depth];
        if (next[depth] == PEV_INVALID)
        {
            EvidenceStatus status = plm_charge(1u);
            if (status.state != PEV_VALID) return status;
            if (!plm_type_ref(current)) return pev_invalid(179u, current.y, PEV_INVALID);
            next[depth] = 0u; count[depth] = 0u; roots[depth] = 0u; nominal[depth] = false;
            if (current.x == 3u)
            {
                uint4 low; uint4 high;
                if (!plm_node(current.y, false, low, high)) return pev_invalid(179u, current.y, PEV_INVALID);
                if (low.x == 1u)
                {
                    nominal[depth] = true;
                    uint atoms;
                    if (!pev_table_count(1u, atoms)) return pev_invalid(179u, current.y, PEV_INVALID);
                    // Expanded recipes allocate fresh rows. Compare exact full
                    // nominal applications, not row IDs, for ancestor cycles.
                    for (uint ancestor = 0u; ancestor < depth; ancestor++)
                    {
                        if (nominal[ancestor] && scoped_type_refs_equal_graphs<NativeLayoutTypeGraph, NativeLayoutTypeGraph>(
                            current.x, current.y, PEV_INVALID,
                            references[ancestor].x, references[ancestor].y, PEV_INVALID,
                            plm_used(0u), plm_used(0u), atoms))
                            return pev_invalid(180u, current.y, references[ancestor].y);
                    }
                    status = plm_expand_nominal(current.y, roots[depth], count[depth]);
                    if (status.state != PEV_VALID) return status;
                }
                else if (low.x == 2u) count[depth] = 1u;
                // slice/reference (3/4) are complete terminal descriptors.
            }
        }
        if (next[depth] == count[depth])
        {
            if (current.x == 3u)
            {
                // Postorder publication makes every by-value child a complete
                // GPU-computed leaf before its parent is evaluated. Thus the
                // shared evaluator does not repeatedly walk the expanded tree.
                uint words = concrete_value_words<MaterializedNativeValueLayout>(current.x, current.y);
                if (words == PEV_INVALID) return pev_limit(182u, current.y, PEV_INVALID, PEV_INVALID - 1u);
                uint address;
                if (!plm_address(4u, current.y, 3u, 1u, false, address)) return pev_invalid(171u, 4u, current.y);
                program_evidence_native_layout_work[address] = words;
            }
            if (depth == 0u) return pev_ok();
            depth--; continue;
        }
        uint2 child;
        if (nominal[depth])
        {
            if (!plm_read2(3u, roots[depth] + next[depth], 0u, false, child))
                return pev_invalid(179u, current.y, roots[depth] + next[depth]);
        }
        else
        {
            uint4 low; uint4 high;
            if (!plm_node(current.y, false, low, high) || low.x != 2u)
                return pev_invalid(179u, current.y, PEV_INVALID);
            child = high.xy;
        }
        next[depth]++;
        if (depth + 1u == PEV_DEPTH_LIMIT)
            return pev_limit(181u, current.y, depth + 2u, PEV_DEPTH_LIMIT);
        depth++; references[depth] = child; next[depth] = PEV_INVALID;
    }
}

public struct MaterializedNativeValueLayout : IConcreteValueLayout
{
    public static uint leaf_words(uint tag, uint payload)
    {
        if (tag == 1u) return scalar_is_known(payload) ? (payload == SCALAR_STR ? 2u : 1u) : PEV_INVALID;
        uint4 low; uint4 high;
        if (tag != 3u || !plm_node(payload, false, low, high)) return PEV_INVALID;
        if (low.x == 3u) return NATIVE_SLICE_WORDS;
        if (low.x == 4u) return 1u;
        uint4 layout;
        return plm_read4(4u, payload, 0u, false, layout) ? layout.w : PEV_INVALID;
    }
    public static uint group_count(uint tag, uint payload)
    {
        uint4 low; uint4 high; uint4 layout;
        if (tag != 3u || !plm_node(payload, false, low, high)) return 0u;
        uint count;
        if (low.x == 2u) return plm_constant_count(high.zw, count) ? 1u : 0u;
        return low.x == 1u && plm_read4(4u, payload, 0u, false, layout) ? layout.y : 0u;
    }
    public static uint overhead(uint tag, uint payload)
    {
        uint4 low; uint4 high; uint recipe; uint4 row; uint4 tail;
        if (tag != 3u || !plm_node(payload, false, low, high)) return 0u;
        if (low.x == 2u) return 0u;
        return low.x == 1u && plr_recipe_for_nominal(low.y, recipe) && plr_read_recipe(recipe, row, tail)
            ? (row.z == 2u ? 1u : 0u) : PEV_INVALID;
    }
    public static uint repetitions(uint tag, uint payload)
    {
        uint4 low; uint4 high;
        if (tag != 3u) return 1u;
        if (!plm_node(payload, false, low, high)) return PEV_INVALID;
        uint4 layout;
        // Cached widths are complete values, including array repetition. The
        // shared evaluator multiplies repetitions even for a complete leaf.
        if (plm_read4(4u, payload, 0u, false, layout) && layout.w != PEV_INVALID) return 1u;
        uint count;
        return low.x == 2u ? (plm_constant_count(high.zw, count) ? count : PEV_INVALID) : 1u;
    }
    public static uint payload_count(uint tag, uint payload, uint group)
    {
        uint4 low; uint4 high; uint4 layout; uint2 span;
        if (tag != 3u || !plm_node(payload, false, low, high)) return PEV_INVALID;
        if (low.x == 2u) return group == 0u ? 1u : PEV_INVALID;
        return low.x == 1u && plm_read4(4u, payload, 0u, false, layout) && group < layout.y &&
            plm_read2(2u, layout.x + group, 0u, false, span) ? span.y : PEV_INVALID;
    }
    public static bool payload_ref(uint tag, uint payload, uint group, uint ordinal,
        out uint child_tag, out uint child_payload)
    {
        child_tag = 0u; child_payload = PEV_INVALID;
        uint4 low; uint4 high; uint4 layout; uint2 span; uint2 child;
        if (tag != 3u || !plm_node(payload, false, low, high)) return false;
        if (low.x == 2u)
        {
            if (group != 0u || ordinal != 0u) return false;
            child_tag = high.x; child_payload = high.y; return plm_type_ref(high.xy);
        }
        if (low.x != 1u || !plm_read4(4u, payload, 0u, false, layout) || group >= layout.y ||
            !plm_read2(2u, layout.x + group, 0u, false, span) || ordinal >= span.y ||
            !plm_read2(3u, span.x + ordinal, 0u, false, child)) return false;
        child_tag = child.x; child_payload = child.y; return plm_type_ref(child);
    }
}

public EvidenceStatus plm_materialize(uint2 source)
{
    uint2 root;
    EvidenceStatus status = plm_copy_closed_root<SameProofNormalizationGraph<SolverProofTermGraph>,
        SolverProofBindings>(source, PEV_INVALID, PEV_INVALID, root);
    if (status.state != PEV_VALID) return status;
    // Only this prefix is the requested semantic type. Later recipe payload
    // expansions are private layout work and are not added to the returned type.
    program_evidence_native_layout_work[19u] = plm_used(0u);
    program_evidence_native_layout_work[20u] = plm_used(1u);
    status = plm_expand_value_graph(root);
    if (status.state != PEV_VALID) return status;
    uint words = concrete_value_words<MaterializedNativeValueLayout>(root.x, root.y);
    if (words == PEV_INVALID) return pev_limit(182u, source.y, PEV_INVALID, PEV_INVALID - 1u);
    // Width belongs to this exact immutable source reference and proof arena.
    // Result and receipt become observable only after the dispatch barrier.
    if (!plm_write4(6u, 0u, 0u, uint4(root.x, root.y, words, 1u)))
        return pev_invalid(171u, 6u, 0u);
    return pev_ok();
}
