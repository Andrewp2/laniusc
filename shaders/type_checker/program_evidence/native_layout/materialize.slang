import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.constant_atoms;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.native_layout.recipe_abi;
import type_checker.program_evidence.native_layout.work_abi;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_term_graph;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_scratch;
import type_checker.concrete_value_layout_scratch;
import thread_scratch;
import native_value_layout;
import primitive_types;
import type_checker.concrete_value_layout;
import type_checker.program_evidence.native_layout.work_graph;

// Expands nominal `node` by its recipe: its groups, then each group's roots
// copied closed in the nominal's environment. With `source_copy` it instead
// copies the materialization's source term into `copied`, through the same
// copy site (solver graph side, no environment and no visible owner).
public EvidenceStatus plm_expand_nominal(uint node, bool source_copy, uint2 source,
    out uint first_root, out uint root_count, out uint2 copied)
{
    first_root = 0u; root_count = 0u; copied = uint2(0u, PEV_INVALID);
    uint recipe = 0u; uint4 row = uint4(0u, 0u, 0u, 0u);
    uint first_group = 0u; uint groups = 1u;
    EvidenceStatus status;
    if (!source_copy)
    {
        uint4 nominal; uint4 children; uint4 tail; uint4 owner; uint4 span;
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
        status = plm_charge(tail.x);
        if (status.state != PEV_VALID) return status;
        status = plm_reserve(2u, tail.x, first_group);
        if (status.state != PEV_VALID) return status;
        // Derive the whole root count before writing any group. Memory limits are
        // explicit per job; no tiny body-packet node limit is reused here.
        for (uint group = 0u; group < tail.x; group++)
        {
            uint3 recipe_group;
            if (!plr_read_group(row.w + group, recipe_group) || recipe_group.x != recipe)
                return pev_invalid(178u, node, row.w + group);
            if (recipe_group.z > PEV_INVALID - 1u - root_count)
                return pev_limit(172u, 3u, PEV_INVALID, PEV_INVALID - 1u);
            root_count += recipe_group.z;
        }
        status = plm_reserve(3u, root_count, first_root);
        if (status.state != PEV_VALID) return status;
        groups = tail.x;
    }
    uint root_next = first_root;
    for (uint group = 0u; group < groups; group++)
    {
        // The source copy is one group of one root.
        uint3 recipe_group = uint3(0u, 0u, 1u);
        if (!source_copy)
        {
            if (!plr_read_group(row.w + group, recipe_group) || recipe_group.x != recipe)
                return pev_invalid(178u, node, row.w + group);
            if (!plm_write2(2u, first_group + group, 0u,
                uint2(recipe_group.z == 0u ? 0u : root_next, recipe_group.z)))
                return pev_invalid(171u, 2u, first_group + group);
        }
        for (uint ordinal = 0u; ordinal < recipe_group.z; ordinal++)
        {
            uint2 original = source; uint2 normalized;
            if (!source_copy && !pev_read_root(recipe_group.y + ordinal, original))
                return pev_invalid(178u, node, recipe_group.y + ordinal);
            status = plm_copy_closed_root<PlmCopyGraphs, NativeLayoutRecipeBindings>(original,
                source_copy ? PEV_INVALID : node, source_copy ? PEV_INVALID : row.y,
                source_copy ? PLM_SIDE_SOLVER : 0u, normalized);
            if (status.state != PEV_VALID) return status;
            if (source_copy) { copied = normalized; return pev_ok(); }
            if (!plm_write2(3u, root_next++, 0u, normalized)) return pev_invalid(171u, 3u, root_next - 1u);
        }
    }
    if (root_next - first_root != root_count ||
        !plm_write4(4u, node, 0u, uint4(first_group, groups, first_root, PEV_INVALID)))
        return pev_invalid(178u, node, recipe);
    program_evidence_native_layout_work[15u] = first_group + groups;
    program_evidence_native_layout_work[16u] = first_root + root_count;
    return pev_ok();
}

// Expand only by-value edges. Nominal operand graphs retain full semantics,
// but descriptor referents do not contribute to native value layout.
// root_words is the root's value width, evaluated at the same site as every
// cached node width (a node root's width is that cached width); the caller
// checks it for a non-node root. The walk starts on the source term: its
// first visit copies the source into `root` through the nominal expansion's
// copy site, then the walk restarts on that copy.
public EvidenceStatus plm_expand_value_graph(uint2 source, out uint2 root, out uint root_words)
{
    root = uint2(0u, PEV_INVALID); root_words = PEV_INVALID;
    // The stack lives in thread scratch: per depth, cell0 = (reference, next
    // child, child count), cell1 = (first expanded root, nominal, 0, 0).
    uint depth = 0u; bool copied = false;
    scratch_set_cell(SCRATCH_NATIVE_MATERIALIZE, uint4(source, PEV_INVALID, 0u));
    for (;;)
    {
        uint frame = SCRATCH_NATIVE_MATERIALIZE + depth * 2u;
        uint4 top = scratch_cell(frame);
        uint2 current = top.xy; uint next = top.z; uint count = top.w;
        uint roots = 0u; bool nominal = false;
        // An array's element, read with the array node at its visit. Its only
        // child step follows in the same iteration (count 1), and node rows
        // never change once written.
        bool array_visit = false; uint2 element = uint2(0u, PEV_INVALID);
        if (next == PEV_INVALID)
        {
            EvidenceStatus status;
            bool expand = !copied;
            if (copied)
            {
                status = plm_charge(1u);
                if (status.state != PEV_VALID) return status;
                if (!plm_type_ref(current)) return pev_invalid(179u, current.y, PEV_INVALID);
                next = 0u; count = 0u;
                if (current.x == 3u)
                {
                    uint4 low; uint4 high;
                    if (!plm_node(current.y, false, low, high)) return pev_invalid(179u, current.y, PEV_INVALID);
                    if (low.x == 1u)
                    {
                        nominal = true;
                        uint atoms;
                        if (!pev_table_count(1u, atoms)) return pev_invalid(179u, current.y, PEV_INVALID);
                        // Expanded recipes allocate fresh rows. Compare exact full
                        // nominal applications, not row IDs, for ancestor cycles.
                        for (uint ancestor = 0u; ancestor < depth; ancestor++)
                        {
                            uint ancestor_frame = SCRATCH_NATIVE_MATERIALIZE + ancestor * 2u;
                            uint2 prior = scratch_cell(ancestor_frame).xy;
                            if (scratch_word(ancestor_frame + 1u, 1u) != 0u &&
                                scoped_type_refs_equal_graphs_scratch<NativeLayoutTypeGraph, NativeLayoutTypeGraph>(
                                current.x, current.y, PEV_INVALID, prior.x, prior.y, PEV_INVALID,
                                plm_used(0u), plm_used(0u), atoms))
                                return pev_invalid(180u, current.y, prior.y);
                        }
                        expand = true;
                    }
                    else if (low.x == 2u) { count = 1u; array_visit = true; element = high.xy; }
                    // slice/reference (3/4) are complete terminal descriptors.
                }
            }
            if (expand)
            {
                uint2 copy;
                status = plm_expand_nominal(current.y, !copied, current, roots, count, copy);
                if (status.state != PEV_VALID) return status;
                if (!copied)
                {
                    // Only this prefix is the requested semantic type. Later recipe
                    // payload expansions are private layout work and are not added
                    // to the returned type.
                    program_evidence_native_layout_work[19u] = plm_used(0u);
                    program_evidence_native_layout_work[20u] = plm_used(1u);
                    root = copy; copied = true;
                    scratch_set_cell(SCRATCH_NATIVE_MATERIALIZE, uint4(copy, PEV_INVALID, 0u));
                    continue;
                }
            }
            scratch_set_cell(frame, uint4(current, 0u, count));
            scratch_set_cell(frame + 1u, uint4(roots, nominal ? 1u : 0u, 0u, 0u));
        }
        else
        {
            uint2 expanded = scratch_cell(frame + 1u).xy;
            roots = expanded.x; nominal = expanded.y != 0u;
        }
        if (next == count)
        {
            if (current.x == 3u || depth == 0u)
            {
                // Postorder publication makes every by-value child a complete
                // GPU-computed leaf before its parent is evaluated. Thus the
                // shared evaluator does not repeatedly walk the expanded tree.
                uint words = concrete_value_words_scratch<MaterializedNativeValueLayout>(current.x, current.y);
                if (current.x == 3u)
                {
                    if (words == PEV_INVALID) return pev_limit(182u, current.y, PEV_INVALID, PEV_INVALID - 1u);
                    uint address;
                    if (!plm_address(4u, current.y, 3u, 1u, false, address)) return pev_invalid(171u, 4u, current.y);
                    program_evidence_native_layout_work[address] = words;
                }
                if (depth == 0u) root_words = words;
            }
            if (depth == 0u) return pev_ok();
            depth--; continue;
        }
        uint2 child;
        if (nominal)
        {
            if (!plm_read2(3u, roots + next, 0u, false, child))
                return pev_invalid(179u, current.y, roots + next);
        }
        else
        {
            if (!array_visit) return pev_invalid(179u, current.y, PEV_INVALID);
            child = element;
        }
        scratch_set_word(frame, 2u, next + 1u);
        if (depth + 1u == PEV_DEPTH_LIMIT)
            return pev_limit(181u, current.y, depth + 2u, PEV_DEPTH_LIMIT);
        depth++;
        scratch_set_cell(SCRATCH_NATIVE_MATERIALIZE + depth * 2u, uint4(child, PEV_INVALID, 0u));
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
        // An array's element, or a nominal's group payload: one reference check.
        if (low.x == 2u)
        {
            if (group != 0u || ordinal != 0u) return false;
            child = high.xy;
        }
        else if (low.x != 1u || !plm_read4(4u, payload, 0u, false, layout) || group >= layout.y ||
            !plm_read2(2u, layout.x + group, 0u, false, span) || ordinal >= span.y ||
            !plm_read2(3u, span.x + ordinal, 0u, false, child)) return false;
        child_tag = child.x; child_payload = child.y; return plm_type_ref(child);
    }
}

public EvidenceStatus plm_materialize(uint2 source)
{
    // The source copy, then its value graph (plm_expand_value_graph).
    uint2 root; uint words;
    EvidenceStatus status = plm_expand_value_graph(source, root, words);
    if (status.state != PEV_VALID) return status;
    if (words == PEV_INVALID) return pev_limit(182u, source.y, PEV_INVALID, PEV_INVALID - 1u);
    // Width belongs to this exact immutable source reference and proof arena.
    // Result and receipt become observable only after the dispatch barrier.
    if (!plm_write4(6u, 0u, 0u, uint4(root.x, root.y, words, 1u)))
        return pev_invalid(171u, 6u, 0u);
    return pev_ok();
}
