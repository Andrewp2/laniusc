import type_checker.trait_solver.constant_atoms;
// Exact selected-header ownership for generic trait selection. Inherent method
// resolution keeps its own contract; this adapter is used only by the program
// implementation catalog and proof checker after definition row admission.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.packed_graph;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;

public struct CatalogImplementationPatternGraph : IOwnedConstraintPatternGraph
{
    public static bool constant_value(uint atom, out uint3 value)
    { return ts_constant_atom_value(atom, value); }
    public static uint constant_parameter_scalar(uint parameter)
    { return ts_constant_parameter_scalar(parameter); }
    public static bool constant_projection(uint node, out uint target, out uint2 child)
    { return ts_constant_projection(node, target, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return ts_admitted_parameter_has_domain(reference, constant); }
    public static uint metadata(uint instance, uint field)
    { return ts_graph_metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ts_graph_argument(instance, slot, tag, payload); }
    public static bool owner_parameter_count(uint owner, bool constant, out uint count)
    {
        count = 0u; uint4 header; uint4 span;
        if (!ts_read_admitted_owner(owner, header, span) || span.y > 64u ||
            !ts_row_span(3u, span.x, span.y)) return false;
        [loop]
        for (uint i = 0u; i < span.y; i++)
        {
            uint4 row; uint4 atom;
            if (!ts_read4(3u, span.x + i, 0u, row) || row.x != owner || row.w > 1u ||
                !ts_read_admitted_parameter(row.y, atom) || atom.y != header.x || atom.z != row.w)
                return false;
            if (row.w == (constant ? 1u : 0u)) count++;
        }
        return true;
    }
    public static uint owned_parameter(uint owner, uint reference, bool constant, out uint index)
    {
        index = OWNED_CONSTRAINT_INVALID;
        uint4 header; uint4 span; uint4 parameter;
        if (!ts_read_admitted_owner(owner, header, span) ||
            !ts_read_admitted_parameter(reference, parameter) ||
            parameter.z != (constant ? 1u : 0u)) return OWNED_PARAMETER_INVALID;
        if (parameter.y != header.x) return OWNED_PARAMETER_RIGID;
        uint domain_index = 0u;
        [loop]
        for (uint i = 0u; i < span.y; i++)
        {
            uint4 row;
            if (!ts_read4(3u, span.x + i, 0u, row) || row.x != owner || row.w > 1u)
                return OWNED_PARAMETER_INVALID;
            if (row.w != parameter.z) continue;
            if (row.y == reference)
            { index = domain_index; return OWNED_PARAMETER_BINDABLE; }
            domain_index++;
        }
        // Same binder but no exact declared member is malformed, not a rigid
        // parameter and not a numeric-slot alias of a declared member.
        return OWNED_PARAMETER_INVALID;
    }
}

public EvidenceStatus ts_owned_constraint_status(OwnedConstraintStatus status, uint subject)
{
    if (status.state == OWNED_CONSTRAINT_MATCHED) return ts_ok();
    if (status.state == OWNED_CONSTRAINT_RESOURCE_LIMIT)
        return ts_limit(80u + status.detail, subject, status.required, status.available);
    // Callers interpret NoMatch separately. Treating it as invalid here prevents
    // a future admission caller accidentally turning inequality into success.
    return ts_invalid(80u + status.detail, subject, TS_INVALID);
}
public bool ts_implementation_root(uint implementation, uint ordinal, out uint2 reference)
{
    reference = uint2(0u, TS_INVALID); uint4 low; uint4 middle;
    if (!ts_read4(9u, implementation, 0u, low) || !ts_read4(9u, implementation, 4u, middle) ||
        middle.y > 32u || ordinal > middle.y) return false;
    uint root = ordinal == 0u ? low.w : middle.x + ordinal - 1u;
    return (ordinal == 0u || ts_row_span(7u, middle.x, middle.y)) && ts_read_root(root, reference);
}

// Must follow full goal-shape/visibility admission for EVERY definition. This
// extra pass establishes that even an unused impl's entire header is inferable.
public EvidenceStatus ts_admit_implementation_coverage(uint implementation, OwnedConstraintLimits limits)
{
    uint4 low; uint4 middle; uint nodes; uint atoms;
    if (!ts_read4(9u, implementation, 0u, low) || !ts_read4(9u, implementation, 4u, middle) ||
        middle.y > 32u || !ts_catalog_count(5u, nodes) || !ts_catalog_count(1u, atoms))
        return ts_invalid(1u, implementation, TS_INVALID);
    OwnedConstraintState state;
    OwnedConstraintStatus status = owned_pattern_begin<CatalogImplementationPatternGraph>(
        low.y, nodes, atoms, limits, owned_constraint_frame(0u), state);
    [loop]
    for (uint i = 0u; status.state == OWNED_CONSTRAINT_MATCHED && i <= middle.y; i++)
    {
        uint2 reference;
        if (!ts_implementation_root(implementation, i, reference)) return ts_invalid(1u, implementation, i);
        status = owned_pattern_visit<CatalogImplementationPatternGraph>(reference, state);
    }
    if (status.state == OWNED_CONSTRAINT_MATCHED) status = owned_pattern_finish<CatalogImplementationPatternGraph>(state);
    return ts_owned_constraint_status(status, implementation);
}

// All heads already passed full coverage/shape admission. An early NoMatch is
// consequently a semantic result; malformed unused branches cannot hide here.
public EvidenceStatus ts_implementation_heads_overlap(uint left, uint right,
    OwnedConstraintLimits limits, out bool overlap)
{
    overlap = false;
    uint4 a; uint4 aa; uint4 b; uint4 ba; uint nodes; uint atoms;
    if (!ts_read4(9u, left, 0u, a) || !ts_read4(9u, left, 4u, aa) ||
        !ts_read4(9u, right, 0u, b) || !ts_read4(9u, right, 4u, ba) ||
        !ts_catalog_count(5u, nodes) || !ts_catalog_count(1u, atoms))
        return ts_invalid(1u, left, right);
    if (a.z != b.z || aa.y != ba.y) return ts_ok();
    OwnedConstraintState state;
    // Both heads live in the one catalog graph: share its code for both sides.
    OwnedConstraintStatus status = owned_overlap_begin_pair<
        OwnedConstraintSameGraphPair<CatalogImplementationPatternGraph>>(
        a.y, b.y, nodes, nodes, atoms, limits, owned_constraint_frame(0u), state);
    [loop]
    for (uint i = 0u; status.state == OWNED_CONSTRAINT_MATCHED && i <= aa.y; i++)
    {
        uint2 ar; uint2 br;
        if (!ts_implementation_root(left, i, ar) || !ts_implementation_root(right, i, br))
            return ts_invalid(1u, left, right);
        status = owned_overlap_match_pair<OwnedConstraintSameGraphPair<CatalogImplementationPatternGraph>>(ar, br, state);
    }
    if (status.state == OWNED_CONSTRAINT_NO_MATCH) return ts_ok();
    if (status.state == OWNED_CONSTRAINT_MATCHED)
        status = owned_overlap_finish_pair<OwnedConstraintSameGraphPair<CatalogImplementationPatternGraph>>(state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return ts_owned_constraint_status(status, left);
    overlap = true; return ts_ok();
}
