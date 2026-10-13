// Environment/owner tables are admitted before this graph preflight. This walk
// validates the complete reachable graph before shared hash/equality may run.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.packed_graph;
import type_checker.scoped_type_equality;

static const uint PEV_GRAPH_CONSTANT = 0x80000000u;
static const uint PEV_GRAPH_DOMAIN_EITHER = 0u;
static const uint PEV_GRAPH_DOMAIN_TYPE = 1u;
static const uint PEV_GRAPH_DOMAIN_CONSTANT = 2u;

// Binding values are already in caller scope. Substitute an original owned
// parameter once and clear its environment, including for node replacements.
EvidenceStatus pev_admit_reference_leaf<Graph : IParameterScopedTypeGraph>(
    uint root, uint visible_owner, bool require_closed, inout uint3 reference)
{
    if (reference.x != 1u && reference.x != 2u && reference.x != 3u &&
        reference.x != (PEV_GRAPH_CONSTANT | 1u) &&
        reference.x != (PEV_GRAPH_CONSTANT | 2u))
        return pev_invalid(4u, root, reference.y);
    if (reference.y == PEV_INVALID)
        return pev_invalid(15u, root, reference.y);

    bool constant = reference.x == (PEV_GRAPH_CONSTANT | 2u);
    if (reference.x == 2u || constant)
    {
        if (!Graph.parameter_is_valid(reference.y, constant))
            return pev_invalid(4u, root, reference.y);
        if (reference.z != PEV_INVALID)
        {
            uint replacement_tag; uint replacement_payload;
            if (constant)
            {
                if (!Graph.substitute_constant_parameter(
                    reference.z, reference.y, replacement_tag, replacement_payload))
                    return pev_invalid(9u, root, reference.y);
                if (replacement_tag != 1u && replacement_tag != 2u)
                    return pev_invalid(4u, root, reference.y);
                replacement_tag |= PEV_GRAPH_CONSTANT;
            }
            else
            {
                if (!Graph.substitute_type_parameter(
                    reference.z, reference.y, replacement_tag, replacement_payload))
                    return pev_invalid(9u, root, reference.y);
                if (replacement_tag != 1u && replacement_tag != 2u && replacement_tag != 3u)
                    return pev_invalid(4u, root, reference.y);
            }
            reference = uint3(replacement_tag, replacement_payload, PEV_INVALID);
            if (reference.y == PEV_INVALID)
                return pev_invalid(15u, root, reference.y);
        }
    }

    if (reference.x == 1u)
    {
        if (!pev_scalar_is_valid(reference.y))
            return pev_invalid(4u, root, reference.y);
    }
    else if (reference.x == 2u || reference.x == (PEV_GRAPH_CONSTANT | 2u))
    {
        constant = reference.x == (PEV_GRAPH_CONSTANT | 2u);
        if (!Graph.parameter_is_valid(reference.y, constant))
            return pev_invalid(4u, root, reference.y);
        if (require_closed) return pev_invalid(10u, root, reference.y);
        if (!pev_parameter_visible(reference.y, visible_owner))
            return pev_invalid(3u, root, reference.y);
    }
    return pev_ok();
}

EvidenceStatus pev_admit_root_with_graph<Graph : IParameterScopedTypeGraph>(
    uint root, uint environment, uint visible_owner,
    bool require_closed, out uint visits)
{
    visits = 0u;
    uint2 root_reference; uint node_count;
    if (!pev_read_root(root, root_reference) || !pev_table_count(5u, node_count))
        return pev_invalid(1u, root, PEV_INVALID);

    uint3 references[PEV_DEPTH_LIMIT];
    uint next[PEV_DEPTH_LIMIT];
    uint counts[PEV_DEPTH_LIMIT];
    uint domains[PEV_DEPTH_LIMIT];
    uint depth = 0u;
    references[0u] = uint3(root_reference.x, root_reference.y, environment);
    next[0u] = PEV_INVALID;
    domains[0u] = PEV_GRAPH_DOMAIN_EITHER;

    [loop]
    for (;;)
    {
        uint3 reference = references[depth];
        if (next[depth] == PEV_INVALID)
        {
            // Every entered edge counts, including array lengths and DAG
            // revisits. Substitution normalizes this visit; it adds no frame.
            if (visits == PEV_VISIT_LIMIT)
                return pev_limit(7u, root, PEV_VISIT_LIMIT + 1u, PEV_VISIT_LIMIT);
            visits++;
            EvidenceStatus status = pev_admit_reference_leaf<Graph>(
                root, visible_owner, require_closed, reference);
            if (status.state != PEV_VALID) return status;

            bool constant = reference.x == (PEV_GRAPH_CONSTANT | 1u) ||
                reference.x == (PEV_GRAPH_CONSTANT | 2u);
            if ((domains[depth] == PEV_GRAPH_DOMAIN_TYPE && constant) ||
                (domains[depth] == PEV_GRAPH_DOMAIN_CONSTANT && !constant))
                return pev_invalid(4u, root, reference.y);

            references[depth] = reference;
            next[depth] = 0u;
            counts[depth] = 0u;
            if (reference.x == 3u)
            {
                if (reference.y >= node_count)
                    return pev_invalid(1u, root, reference.y);
                uint admitted_kind = Graph.metadata(reference.y, 0u);
                uint admitted_count = Graph.metadata(reference.y, 2u);
                if (admitted_kind == 1u && admitted_count > 32u)
                    return pev_limit(19u, root, admitted_count, 32u);
                if (!pev_node_is_valid(reference.y)) return pev_invalid(4u, root, reference.y);
                // A substitution may turn a parameter edge into a node, so
                // detect cycles only after normalization of the current ref.
                [loop]
                for (uint ancestor = 0u; ancestor < depth; ancestor++)
                    if (references[ancestor].x == 3u &&
                        references[ancestor].y == reference.y &&
                        references[ancestor].z == reference.z)
                        return pev_invalid(5u, root, reference.y);

                uint kind = Graph.metadata(reference.y, 0u);
                if (kind == 1u)
                {
                    uint count = Graph.metadata(reference.y, 2u);
                    counts[depth] = count;
                }
                else if (kind == 2u) counts[depth] = 2u;
                else if (kind == 3u || kind == 4u) counts[depth] = 1u;
                else return pev_invalid(4u, root, reference.y);
            }
        }

        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return pev_ok();
            depth--;
            continue;
        }

        uint slot = next[depth];
        next[depth] = slot + 1u;
        uint kind = Graph.metadata(reference.y, 0u);
        uint child_tag; uint child_payload;
        uint child_domain = PEV_GRAPH_DOMAIN_TYPE;
        if (kind == 1u)
        {
            if (!Graph.argument(reference.y, slot, child_tag, child_payload))
                return pev_invalid(1u, root, reference.y);
            child_domain = PEV_GRAPH_DOMAIN_EITHER;
        }
        else if (kind == 2u && slot == 1u)
        {
            uint length_kind = Graph.metadata(reference.y, 5u);
            if (length_kind != 1u && length_kind != 2u)
                return pev_invalid(4u, root, reference.y);
            child_tag = PEV_GRAPH_CONSTANT | length_kind;
            child_payload = Graph.metadata(reference.y, 6u);
            child_domain = PEV_GRAPH_DOMAIN_CONSTANT;
        }
        else
        {
            child_tag = Graph.metadata(reference.y, 3u);
            child_payload = Graph.metadata(reference.y, 4u);
        }

        if (depth + 1u == PEV_DEPTH_LIMIT)
            return pev_limit(6u, root, depth + 2u, PEV_DEPTH_LIMIT);
        depth++;
        references[depth] = uint3(child_tag, child_payload, reference.z);
        next[depth] = PEV_INVALID;
        domains[depth] = child_domain;
    }
}

// Batch admission retains full owner-aware substitution. Keep one traversal
// implementation for both graph policies, including every diagnostic/budget.
public EvidenceStatus pev_admit_root(
    uint root, uint environment, uint visible_owner,
    bool require_closed, out uint visits)
{
    return pev_admit_root_with_graph<ProgramEvidenceTypeGraph>(
        root, environment, visible_owner, require_closed, visits);
}

// Catalog callers cannot supply an environment. Symbolic predicate leaves still
// require exact identity and lexical visibility; closed implementations reject
// them through the same shared walker.
public EvidenceStatus pev_admit_catalog_definition_root(
    uint root, uint visible_owner, bool require_closed, out uint visits)
{
    return pev_admit_root_with_graph<CatalogProgramEvidenceTypeGraph>(
        root, PEV_INVALID, visible_owner, require_closed, visits);
}
