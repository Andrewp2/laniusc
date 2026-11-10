import primitive_types;
import constant_value;
import type_checker.concrete_type_equality;
// Complete atom/node/edge/root row admission precedes this walk; lexical
// owners/parameters are admitted frozen catalog rows. This preflight proves
// the remaining contextual graph properties before shared hash/equality.
// Env11 may call it before Binding12, but with no substitution environment;
// its own binding scan is still mandatory. Later substitution callers must
// first admit every supplied environment with its exact owner and scope.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.packed_graph;
import thread_scratch;
import type_checker.scoped_type_equality;

static const uint TS_GRAPH_CONSTANT = 0x80000000u;

// Binding values are already in caller scope. Substitute an original owned
// parameter once and clear its environment, including for node replacements.
EvidenceStatus ts_admit_reference_leaf<Graph : ITsAdmissionGraph>(
    uint root, uint visible_owner, bool require_closed, inout uint3 reference)
{
    if (reference.x != 1u && reference.x != 2u && reference.x != 3u &&
        reference.x != (TS_GRAPH_CONSTANT | 1u) &&
        reference.x != (TS_GRAPH_CONSTANT | 2u) &&
        reference.x != (TS_GRAPH_CONSTANT | 3u))
        return ts_invalid(4u, root, reference.y);
    if (reference.y == TS_INVALID)
        return ts_invalid(15u, root, reference.y);

    bool constant = reference.x == (TS_GRAPH_CONSTANT | 2u);
    if (reference.x == 2u || constant)
    {
        if (!Graph.parameter_is_valid(reference.y, constant))
            return ts_invalid(4u, root, reference.y);
        if (reference.z != TS_INVALID)
        {
            // One substitution call site for both parameter domains.
            uint replacement_tag; uint replacement_payload;
            if (!Graph.substitute_parameter(
                reference.z, reference.y, constant, replacement_tag, replacement_payload))
                return ts_invalid(9u, root, reference.y);
            if (replacement_tag < 1u || replacement_tag > 3u)
                return ts_invalid(4u, root, reference.y);
            if (constant)
            {
                if (constant_reference_scalar<Graph>(uint2(replacement_tag, replacement_payload)) !=
                        Graph.constant_parameter_scalar(reference.y))
                    return ts_invalid(4u, root, reference.y);
                replacement_tag |= TS_GRAPH_CONSTANT;
            }
            reference = uint3(replacement_tag, replacement_payload, TS_INVALID);
            if (reference.y == TS_INVALID)
                return ts_invalid(15u, root, reference.y);
        }
    }

    if (reference.x == 1u)
    {
        if (!ts_scalar_is_valid(reference.y))
            return ts_invalid(4u, root, reference.y);
    }
    else if (reference.x == 2u || reference.x == (TS_GRAPH_CONSTANT | 2u))
    {
        constant = reference.x == (TS_GRAPH_CONSTANT | 2u);
        if (!Graph.parameter_is_valid(reference.y, constant))
            return ts_invalid(4u, root, reference.y);
        if (require_closed) return ts_invalid(10u, root, reference.y);
        if (!ts_admitted_parameter_visible(reference.y, visible_owner))
            return ts_invalid(3u, root, reference.y);
    }
    return ts_ok();
}

EvidenceStatus ts_admit_root_with_graph<Graph : ITsAdmissionGraph>(
    uint root, uint environment, uint visible_owner,
    bool require_closed, out uint visits)
{
    visits = 0u;
    uint2 root_reference; uint node_count;
    if (!ts_read_root(root, root_reference) || !ts_table_count(5u, node_count))
        return ts_invalid(1u, root, TS_INVALID);

    // The stack lives in thread scratch: per depth, cell0 = (reference, next
    // child) and cell1 = (child count, domain, count context).
    uint depth = 0u;
    scratch_set_cell(SCRATCH_TS_GRAPH, uint4(root_reference.x, root_reference.y, environment, TS_INVALID));
    scratch_set_cell(SCRATCH_TS_GRAPH + 1u, uint4(0u, TS_ADMITTED_DOMAIN_EITHER, 0u, 0u));

    [loop]
    for (;;)
    {
        uint frame = SCRATCH_TS_GRAPH + depth * 2u;
        uint4 top = scratch_cell(frame); uint4 shape = scratch_cell(frame + 1u);
        uint3 reference = top.xyz; uint next = top.w;
        if (next == TS_INVALID)
        {
            // Every entered edge counts, including array lengths and DAG
            // revisits. Substitution normalizes this visit; it adds no frame.
            if (visits == TS_VISIT_LIMIT)
                return ts_limit(7u, root, TS_VISIT_LIMIT + 1u, TS_VISIT_LIMIT);
            visits++;
            EvidenceStatus status = ts_admit_reference_leaf<Graph>(
                root, visible_owner, require_closed, reference);
            if (status.state != TS_VALID) return status;

            bool constant = reference.x == (TS_GRAPH_CONSTANT | 1u) ||
                reference.x == (TS_GRAPH_CONSTANT | 2u) ||
                reference.x == (TS_GRAPH_CONSTANT | 3u);
            if ((shape.y == TS_ADMITTED_DOMAIN_TYPE && constant) ||
                (shape.y == TS_ADMITTED_DOMAIN_CONSTANT && !constant))
                return ts_invalid(4u, root, reference.y);

            if (constant)
            {
                uint3 constant_ref = uint3(reference.x & ~TS_GRAPH_CONSTANT, reference.yz);
                ConstantReferenceDescriptor descriptor;
                if (!scoped_constant_reference<Graph>(constant_ref, TS_INVALID, descriptor))
                    return ts_invalid(4u, root, reference.y);
                if (shape.z != 0u)
                {
                    uint scalar; uint count;
                    if (!constant_descriptor_result_scalar<Graph>(descriptor, scalar) || !scalar_is_integer(scalar) ||
                        (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE && !constant_value_to_count(descriptor.value, count)))
                        return ts_invalid(4u, root, reference.y);
                }
            }
            next = 0u; shape.x = 0u;
            if (reference.x == 3u || reference.x == (TS_GRAPH_CONSTANT | 3u))
            {
                if (reference.y >= node_count)
                    return ts_invalid(1u, root, reference.y);
                uint4 node; uint4 children;
                if (!ts_read_admitted_node(reference.y, node, children) ||
                    (constant ? node.x != 5u : node.x > 4u))
                    return ts_invalid(4u, root, reference.y);
                // A substitution may turn a parameter edge into a node, so
                // detect cycles only after normalization of the current ref.
                [loop]
                for (uint ancestor = 0u; ancestor < depth; ancestor++)
                {
                    uint3 prior = scratch_cell(SCRATCH_TS_GRAPH + ancestor * 2u).xyz;
                    if (prior.x == reference.x && prior.y == reference.y && prior.z == reference.z)
                        return ts_invalid(5u, root, reference.y);
                }

                shape.x = node.x == 1u ? node.w : (node.x == 2u ? 2u : 1u);
            }
            scratch_set_cell(frame + 1u, shape);
        }

        if (next == shape.x)
        {
            if (depth == 0u) return ts_ok();
            depth--;
            continue;
        }

        uint slot = next;
        scratch_set_cell(frame, uint4(reference, slot + 1u));
        uint4 node; uint4 children; uint2 child; uint child_domain;
        if (!ts_read_admitted_node(reference.y, node, children) ||
            !ts_read_admitted_child(node, children, slot, child, child_domain))
            return ts_invalid(4u, root, reference.y);

        if (depth + 1u == TS_DEPTH_LIMIT)
            return ts_limit(6u, root, depth + 2u, TS_DEPTH_LIMIT);
        depth++;
        bool count_context = (node.x == 2u && slot == 1u) || node.x == 5u;
        scratch_set_cell(frame + 2u, uint4(child.x, child.y, reference.z, TS_INVALID));
        scratch_set_cell(frame + 3u, uint4(0u, child_domain, count_context ? 1u : 0u, 0u));
    }
}

// Batch admission retains full owner-aware substitution. Keep one traversal
// implementation for both graph policies, including every diagnostic/budget.
public EvidenceStatus ts_admit_root(
    uint root, uint environment, uint visible_owner,
    bool require_closed, out uint visits)
{
    return ts_admit_root_with_graph<TraitSolverTypeGraph>(
        root, environment, visible_owner, require_closed, visits);
}

// Catalog callers cannot supply an environment. Symbolic predicate leaves still
// require exact identity and lexical visibility; closed implementations reject
// them through the same shared walker.
public EvidenceStatus ts_admit_catalog_definition_root(
    uint root, uint visible_owner, bool require_closed, out uint visits)
{
    return ts_admit_root_with_graph<CatalogTraitSolverTypeGraph>(
        root, TS_INVALID, visible_owner, require_closed, visits);
}
