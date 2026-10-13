import type_checker.program_evidence.constant_atoms;
// Admit every catalog row and reduce all failures before publishing a catalog.
// These local prefix checks establish immutable transitive closure only after
// that barrier. A valid individual row is not a whole-catalog certificate.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.definition_admission;
import type_checker.owned_type_constraint_contract;

// Public (library, unit) membership and exact immutable snapshot/alias matching
// remain host registry preconditions. Do not turn them into an unbounded GPU
// scan. Atom interning is exact and unique across the catalog and batch arenas.
public bool pev_catalog_span(uint table, uint first, uint count)
{
    EvidenceTable descriptor;
    return pev_descriptor(table, descriptor) &&
        (count != 0u || first == 0u) && first <= descriptor.catalog_count &&
        count <= descriptor.catalog_count - first;
}
public bool pev_catalog_row(uint table, uint row)
{ return pev_catalog_span(table, row, 1u); }

bool pev_catalog_binder(uint atom)
{
    uint4 low; uint4 high;
    if (!pev_catalog_row(1u, atom) || !pev_atom(atom, low, high) ||
        !pev_binder_is_valid(atom)) return false;
    return low.x == 3u || (low.x == 4u && pev_catalog_row(0u, low.y));
}
bool pev_catalog_parameter(uint atom, bool constant)
{
    uint4 low; uint4 high;
    return pev_catalog_row(1u, atom) && pev_atom(atom, low, high) &&
        pev_parameter_is_valid(atom, constant) && pev_catalog_binder(low.y);
}
bool pev_catalog_nominal(uint atom)
{
    uint4 low; uint4 high;
    return pev_catalog_row(1u, atom) && pev_atom(atom, low, high) &&
        pev_nominal_is_valid(atom) && (low.x == 1u || pev_catalog_row(0u, low.y));
}
bool pev_catalog_callable_atom(uint atom)
{
    uint4 low; uint4 high;
    return pev_catalog_row(1u, atom) && pev_atom(atom, low, high) &&
        pev_callable_atom_is_valid(atom) && (low.x == 8u || pev_catalog_row(0u, low.y));
}
public bool pev_catalog_type_ref(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    if (reference.x == 1u) return pev_scalar_is_valid(reference.y);
    if (reference.x == 2u) return pev_catalog_parameter(reference.y, false);
    return reference.x == 3u && pev_catalog_row(5u, reference.y);
}
public bool pev_catalog_constant_ref(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    uint3 value; uint target; uint2 child;
    return (reference.x == 0x80000001u && pev_catalog_row(1u, reference.y) &&
            pev_constant_atom_value(reference.y, value)) ||
        (reference.x == 0x80000002u && pev_catalog_parameter(reference.y, true)) ||
        (reference.x == 0x80000003u && pev_catalog_row(5u, reference.y) &&
            pev_constant_projection(reference.y, target, child));
}
public bool pev_catalog_ref(uint2 reference)
{ return pev_catalog_type_ref(reference) || pev_catalog_constant_ref(reference); }

public EvidenceStatus pev_admit_catalog_atom(uint atom)
{
    uint4 low; uint4 high;
    if (!pev_catalog_row(1u, atom) || !pev_atom(atom, low, high))
        return pev_invalid(1u, atom, 1u);
    bool valid = false;
    switch (low.x)
    {
    case 1u: case 2u:
        valid = pev_catalog_nominal(atom); break;
    case 3u: case 4u:
        valid = pev_catalog_binder(atom); break;
    case 5u:
        if (low.z > 1u) return pev_invalid(4u, atom, low.z);
        valid = pev_catalog_parameter(atom, low.z == 1u); break;
    case 6u: case 10u:
        valid = low.y != PEV_INVALID && low.z != PEV_INVALID && low.w != PEV_INVALID &&
            all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 7u:
        valid = pev_catalog_row(0u, low.y) && pev_snapshot_is_valid(low.y) &&
            low.z != PEV_INVALID && low.w == 0u && all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 8u: case 9u:
        // An accepted private callable can retain a method-tagged native symbol.
        // Public/private atom kind follows its accepted alias, not symbol bits.
        valid = pev_catalog_callable_atom(atom); break;
    case 11u:
        valid = pev_catalog_row(0u, low.y) && pev_snapshot_is_valid(low.y) &&
            low.z != PEV_INVALID && low.w != PEV_INVALID &&
            all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 12u:
    { uint3 value; valid = pev_constant_atom_value(atom, value); break; }
    default: return pev_invalid(2u, atom, low.x);
    }
    if (!valid) return pev_invalid(2u, atom, low.x);
    return pev_ok();
}

public EvidenceStatus pev_admit_catalog_node(uint node)
{
    uint4 low; uint4 high;
    if (!pev_catalog_row(5u, node) || !pev_read8(5u, node, low, high)) return pev_invalid(1u, node, 5u);
    if (low.x == 1u && low.w > 32u) return pev_limit(19u, node, low.w, 32u);
    if (!pev_node_is_valid(node)) return pev_invalid(4u, node, PEV_INVALID);
    if (low.x == 1u)
    {
        if (!pev_catalog_nominal(low.y) || !pev_catalog_span(6u, low.z, low.w))
            return pev_invalid(1u, node, low.y);
        for (uint i = 0u; i < low.w; i++)
        {
            uint2 child;
            if (!pev_read2(6u, low.z + i, 0u, child) || !pev_catalog_ref(child))
                return pev_invalid(4u, node, low.z + i);
        }
    }
    else if (low.x == 5u)
    {
        if (!pev_catalog_constant_ref(high.xy)) return pev_invalid(4u, node, high.y);
    }
    else
    {
        if (!pev_catalog_type_ref(high.xy) ||
            (low.x == 2u && !pev_catalog_constant_ref(high.zw)))
            return pev_invalid(4u, node, PEV_INVALID);
    }
    // No recursive walk for an otherwise unused Node. Goal-root admission owns
    // cycle, depth, work, closure, and lexical parameter visibility validation.
    return pev_ok();
}

public EvidenceStatus pev_admit_catalog_owner(uint owner)
{
    uint4 low; uint4 high; uint callable;
    if (!pev_catalog_row(2u, owner) || !pev_read8(2u, owner, low, high) || !pev_word(2u, owner, 8u, callable))
        return pev_invalid(1u, owner, 2u);
    if (high.y > 64u) return pev_limit(19u, owner, high.y, 64u);
    if (!pev_catalog_binder(low.x) || !pev_catalog_row(0u, low.y) ||
        (low.w != PEV_INVALID && !pev_catalog_row(2u, low.w)) ||
        !pev_catalog_span(3u, high.x, high.y) || !pev_catalog_span(8u, high.z, high.w) ||
        (callable != PEV_INVALID && !pev_catalog_row(4u, callable)))
        return pev_invalid(3u, owner, PEV_INVALID);
    // Check both directions. Predicate admission verifies its claimed owner's
    // span; this rejects another owner borrowing that same predicate span.
    for (uint i = 0u; i < high.w; i++)
    {
        uint predicate_owner;
        if (!pev_word(8u, high.z + i, 1u, predicate_owner) || predicate_owner != owner)
            return pev_invalid(3u, owner, high.z + i);
    }
    uint types; uint constants;
    return pev_admit_owner_chain(owner, types, constants);
}

public EvidenceStatus pev_admit_catalog_parameter(uint row)
{
    uint4 parameter; uint4 span;
    if (!pev_catalog_row(3u, row) || !pev_read4(3u, row, 0u, parameter) ||
        !pev_catalog_row(2u, parameter.x)) return pev_invalid(1u, row, 3u);
    if (parameter.w > 1u || !pev_catalog_parameter(parameter.y, parameter.w == 1u) ||
        !pev_parameter_row_is_valid(row, parameter.x))
        return pev_invalid(4u, row, parameter.y);
    // Owner2 finished before Parameter3. Preserve reverse span membership
    // without repeating its full chain validation for each parameter row.
    if (!pev_read4(2u, parameter.x, 4u, span) || row < span.x || row - span.x >= span.y)
        return pev_invalid(3u, row, parameter.x);
    return pev_ok();
}

public EvidenceStatus pev_admit_catalog_callable(uint row)
{
    uint4 callable;
    if (!pev_catalog_row(4u, row) || !pev_read4(4u, row, 0u, callable) ||
        !pev_catalog_callable_atom(callable.x) || !pev_catalog_row(2u, callable.y))
        return pev_invalid(14u, row, PEV_INVALID);
    return pev_admit_callable(row);
}

public EvidenceStatus pev_admit_catalog_predicate(uint row)
{
    uint4 low; uint4 high;
    if (!pev_catalog_row(8u, row) || !pev_read8(8u, row, low, high)) return pev_invalid(1u, row, 8u);
    if (high.y > 32u) return pev_limit(19u, row, high.y, 32u);
    if (!pev_catalog_row(1u, low.x) || !pev_catalog_row(2u, low.y) ||
        !pev_catalog_nominal(low.z) || !pev_catalog_row(7u, low.w) ||
        !pev_catalog_span(7u, high.x, high.y)) return pev_invalid(1u, row, PEV_INVALID);
    EvidenceStatus status = pev_admit_catalog_atom(low.x);
    if (status.state != PEV_VALID) return status;
    return pev_admit_predicate(row);
}

public EvidenceStatus pev_admit_catalog_implementation(uint row)
{
    uint4 low; uint4 middle; uint4 high;
    if (!pev_catalog_row(9u, row) || !pev_read8(9u, row, low, middle) || !pev_read4(9u, row, 8u, high))
        return pev_invalid(1u, row, 9u);
    if (middle.y > 32u) return pev_limit(19u, row, middle.y, 32u);
    if (!pev_catalog_row(1u, low.x) || !pev_catalog_row(2u, low.y) ||
        !pev_catalog_nominal(low.z) || !pev_catalog_row(7u, low.w) ||
        !pev_catalog_span(7u, middle.x, middle.y) ||
        !pev_catalog_span(10u, middle.z, middle.w) ||
        !pev_catalog_span(8u, high.x, high.y)) return pev_invalid(1u, row, PEV_INVALID);
    EvidenceStatus status = pev_admit_catalog_atom(low.x);
    if (status.state != PEV_VALID) return status;
    // Complete head coverage precedes both exact/coarse index publication and
    // any early match. Up to33 admitted roots retain their prior visit budget.
    OwnedConstraintLimits limits = { PEV_DEPTH_LIMIT, 0u, 33u * PEV_VISIT_LIMIT, 0u };
    return pev_admit_implementation_with_owned_solver(row, limits);
}

public EvidenceStatus pev_admit_catalog_method(uint row)
{
    uint4 method; uint2 tail; uint4 implementation; uint4 span; uint parent;
    if (!pev_catalog_row(10u, row) || !pev_read4(10u, row, 0u, method) ||
        !pev_read2(10u, row, 4u, tail) || !pev_catalog_row(9u, method.x) ||
        !pev_read8(9u, method.x, implementation, span) ||
        !pev_catalog_span(10u, span.z, span.w) || row < span.z || row - span.z >= span.w)
        return pev_invalid(1u, row, 10u);
    if (method.y == PEV_INVALID || (method.y & 0xc0000000u) != 0x80000000u ||
        method.w > 3u || tail.y != 0u || !pev_catalog_callable_atom(method.z) ||
        !pev_catalog_row(2u, tail.x) || !pev_owned_identity_matches(method.z, tail.x, 8u, 9u) ||
        !pev_word(2u, tail.x, 3u, parent) || parent != implementation.y)
        return pev_invalid(14u, row, method.x);
    if (row != span.z)
    {
        uint previous;
        if (!pev_word(10u, row - 1u, 1u, previous) || previous >= method.y)
            return pev_invalid(14u, row, row - 1u);
    }
    EvidenceStatus status = pev_admit_inherited_method_environment(tail.x, implementation.y);
    if (status.state != PEV_VALID) return status;
    // Exact membership of target atom + owner in accepted Callable records is
    // checked by the catalog index phase; no per-method full-table scan here.
    return pev_ok();
}

public EvidenceStatus pev_admit_catalog_snapshot(uint row)
{
    if (!pev_catalog_row(0u, row)) return pev_invalid(1u, row, 0u);
    if (!pev_snapshot_is_valid(row)) return pev_invalid(2u, row, 0u);
    return pev_ok();
}
public EvidenceStatus pev_admit_catalog_edge(uint row)
{
    if (!pev_catalog_row(6u, row)) return pev_invalid(1u, row, 6u);
    uint2 reference;
    if (!pev_read2(6u, row, 0u, reference) || !pev_catalog_ref(reference))
        return pev_invalid(4u, row, 6u);
    return pev_ok();
}
public EvidenceStatus pev_admit_catalog_root(uint row)
{
    if (!pev_catalog_row(7u, row)) return pev_invalid(1u, row, 7u);
    uint2 reference;
    if (!pev_read2(7u, row, 0u, reference) || !pev_catalog_ref(reference))
        return pev_invalid(4u, row, 7u);
    return pev_ok();
}
