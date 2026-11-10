import type_checker.trait_solver.constant_atoms;
// Admit every catalog row and reduce all failures before publishing a catalog.
// These local prefix checks establish immutable transitive closure only after
// that barrier. A valid individual row is not a whole-catalog certificate.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.definition_admission;
import type_checker.owned_type_constraint_contract;

// Public (library, unit) membership and exact immutable snapshot/alias matching
// remain host registry preconditions. Do not turn them into an unbounded GPU
// scan. Atom interning is exact and unique across the catalog and batch arenas.
public bool ts_catalog_span(uint table, uint first, uint count)
{
    EvidenceTable descriptor;
    return ts_descriptor(table, descriptor) &&
        (count != 0u || first == 0u) && first <= descriptor.catalog_count &&
        count <= descriptor.catalog_count - first;
}
public bool ts_catalog_row(uint table, uint row)
{ return ts_catalog_span(table, row, 1u); }

bool ts_catalog_binder(uint atom)
{
    uint4 low; uint4 high;
    if (!ts_catalog_row(1u, atom) || !ts_atom(atom, low, high) ||
        !ts_binder_is_valid(atom)) return false;
    return low.x == 3u || (low.x == 4u && ts_catalog_row(0u, low.y));
}
bool ts_catalog_parameter(uint atom, bool constant)
{
    uint4 low; uint4 high;
    return ts_catalog_row(1u, atom) && ts_atom(atom, low, high) &&
        ts_parameter_is_valid(atom, constant) && ts_catalog_binder(low.y);
}
bool ts_catalog_nominal(uint atom)
{
    uint4 low; uint4 high;
    return ts_catalog_row(1u, atom) && ts_atom(atom, low, high) &&
        ts_nominal_is_valid(atom) && (low.x == 1u || ts_catalog_row(0u, low.y));
}
bool ts_catalog_callable_atom(uint atom)
{
    uint4 low; uint4 high;
    return ts_catalog_row(1u, atom) && ts_atom(atom, low, high) &&
        ts_callable_atom_is_valid(atom) && (low.x == 8u || ts_catalog_row(0u, low.y));
}
public bool ts_catalog_type_ref(uint2 reference)
{
    if (reference.y == TS_INVALID) return false;
    if (reference.x == 1u) return ts_scalar_is_valid(reference.y);
    if (reference.x == 2u) return ts_catalog_parameter(reference.y, false);
    return reference.x == 3u && ts_catalog_row(5u, reference.y);
}
public bool ts_catalog_constant_ref(uint2 reference)
{
    if (reference.y == TS_INVALID) return false;
    uint3 value; uint target; uint2 child;
    return (reference.x == 0x80000001u && ts_catalog_row(1u, reference.y) &&
            ts_constant_atom_value(reference.y, value)) ||
        (reference.x == 0x80000002u && ts_catalog_parameter(reference.y, true)) ||
        (reference.x == 0x80000003u && ts_catalog_row(5u, reference.y) &&
            ts_constant_projection(reference.y, target, child));
}
public bool ts_catalog_ref(uint2 reference)
{ return ts_catalog_type_ref(reference) || ts_catalog_constant_ref(reference); }

public EvidenceStatus ts_admit_catalog_atom(uint atom)
{
    uint4 low; uint4 high;
    if (!ts_catalog_row(1u, atom) || !ts_atom(atom, low, high))
        return ts_invalid(1u, atom, 1u);
    bool valid = false;
    switch (low.x)
    {
    case 1u: case 2u:
        valid = ts_catalog_nominal(atom); break;
    case 3u: case 4u:
        valid = ts_catalog_binder(atom); break;
    case 5u:
        if (low.z > 1u) return ts_invalid(4u, atom, low.z);
        valid = ts_catalog_parameter(atom, low.z == 1u); break;
    case 6u: case 10u:
        valid = low.y != TS_INVALID && low.z != TS_INVALID && low.w != TS_INVALID &&
            all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 7u:
        valid = ts_catalog_row(0u, low.y) && ts_snapshot_is_valid(low.y) &&
            low.z != TS_INVALID && low.w == 0u && all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 8u: case 9u:
        // An accepted private callable can retain a method-tagged native symbol.
        // Public/private atom kind follows its accepted alias, not symbol bits.
        valid = ts_catalog_callable_atom(atom); break;
    case 11u:
        valid = ts_catalog_row(0u, low.y) && ts_snapshot_is_valid(low.y) &&
            low.z != TS_INVALID && low.w != TS_INVALID &&
            all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 12u:
    { uint3 value; valid = ts_constant_atom_value(atom, value); break; }
    default: return ts_invalid(2u, atom, low.x);
    }
    if (!valid) return ts_invalid(2u, atom, low.x);
    return ts_ok();
}

public EvidenceStatus ts_admit_catalog_node(uint node)
{
    uint4 low; uint4 high;
    if (!ts_catalog_row(5u, node) || !ts_read8(5u, node, low, high)) return ts_invalid(1u, node, 5u);
    if (low.x == 1u && low.w > 32u) return ts_limit(19u, node, low.w, 32u);
    if (!ts_node_is_valid(node)) return ts_invalid(4u, node, TS_INVALID);
    if (low.x == 1u)
    {
        if (!ts_catalog_nominal(low.y) || !ts_catalog_span(6u, low.z, low.w))
            return ts_invalid(1u, node, low.y);
        for (uint i = 0u; i < low.w; i++)
        {
            uint2 child;
            if (!ts_read2(6u, low.z + i, 0u, child) || !ts_catalog_ref(child))
                return ts_invalid(4u, node, low.z + i);
        }
    }
    else if (low.x == 5u)
    {
        if (!ts_catalog_constant_ref(high.xy)) return ts_invalid(4u, node, high.y);
    }
    else
    {
        if (!ts_catalog_type_ref(high.xy) ||
            (low.x == 2u && !ts_catalog_constant_ref(high.zw)))
            return ts_invalid(4u, node, TS_INVALID);
    }
    // No recursive walk for an otherwise unused Node. Goal-root admission owns
    // cycle, depth, work, closure, and lexical parameter visibility validation.
    return ts_ok();
}

public EvidenceStatus ts_admit_catalog_owner(uint owner)
{
    uint4 low; uint4 high; uint callable;
    if (!ts_catalog_row(2u, owner) || !ts_read8(2u, owner, low, high) || !ts_word(2u, owner, 8u, callable))
        return ts_invalid(1u, owner, 2u);
    if (high.y > 64u) return ts_limit(19u, owner, high.y, 64u);
    if (!ts_catalog_binder(low.x) || !ts_catalog_row(0u, low.y) ||
        (low.w != TS_INVALID && !ts_catalog_row(2u, low.w)) ||
        !ts_catalog_span(3u, high.x, high.y) || !ts_catalog_span(8u, high.z, high.w) ||
        (callable != TS_INVALID && !ts_catalog_row(4u, callable)))
        return ts_invalid(3u, owner, TS_INVALID);
    // Check both directions. Predicate admission verifies its claimed owner's
    // span; this rejects another owner borrowing that same predicate span.
    for (uint i = 0u; i < high.w; i++)
    {
        uint predicate_owner;
        if (!ts_word(8u, high.z + i, 1u, predicate_owner) || predicate_owner != owner)
            return ts_invalid(3u, owner, high.z + i);
    }
    uint types; uint constants;
    return ts_admit_owner_chain(owner, types, constants);
}

public EvidenceStatus ts_admit_catalog_parameter(uint row)
{
    uint4 parameter; uint4 span;
    if (!ts_catalog_row(3u, row) || !ts_read4(3u, row, 0u, parameter) ||
        !ts_catalog_row(2u, parameter.x)) return ts_invalid(1u, row, 3u);
    if (parameter.w > 1u || !ts_catalog_parameter(parameter.y, parameter.w == 1u) ||
        !ts_parameter_row_is_valid(row, parameter.x))
        return ts_invalid(4u, row, parameter.y);
    // Owner2 finished before Parameter3. Preserve reverse span membership
    // without repeating its full chain validation for each parameter row.
    if (!ts_read4(2u, parameter.x, 4u, span) || row < span.x || row - span.x >= span.y)
        return ts_invalid(3u, row, parameter.x);
    return ts_ok();
}

public EvidenceStatus ts_admit_catalog_callable(uint row)
{
    uint4 callable;
    if (!ts_catalog_row(4u, row) || !ts_read4(4u, row, 0u, callable) ||
        !ts_catalog_callable_atom(callable.x) || !ts_catalog_row(2u, callable.y))
        return ts_invalid(14u, row, TS_INVALID);
    return ts_admit_callable(row);
}

public EvidenceStatus ts_admit_catalog_predicate(uint row)
{
    uint4 low; uint4 high;
    if (!ts_catalog_row(8u, row) || !ts_read8(8u, row, low, high)) return ts_invalid(1u, row, 8u);
    if (high.y > 32u) return ts_limit(19u, row, high.y, 32u);
    if (!ts_catalog_row(1u, low.x) || !ts_catalog_row(2u, low.y) ||
        !ts_catalog_nominal(low.z) || !ts_catalog_row(7u, low.w) ||
        !ts_catalog_span(7u, high.x, high.y)) return ts_invalid(1u, row, TS_INVALID);
    EvidenceStatus status = ts_admit_catalog_atom(low.x);
    if (status.state != TS_VALID) return status;
    return ts_admit_predicate(row);
}

// 02_09 admits an implementation row in two dispatches (definition_admission:
// ts_admit_implementation_head, then ts_admit_implementation_members).
public EvidenceStatus ts_admit_catalog_implementation_head(uint row)
{
    uint4 low; uint4 middle; uint4 high;
    if (!ts_catalog_row(9u, row) || !ts_read8(9u, row, low, middle) || !ts_read4(9u, row, 8u, high))
        return ts_invalid(1u, row, 9u);
    if (middle.y > 32u) return ts_limit(19u, row, middle.y, 32u);
    if (!ts_catalog_row(1u, low.x) || !ts_catalog_row(2u, low.y) ||
        !ts_catalog_nominal(low.z) || !ts_catalog_row(7u, low.w) ||
        !ts_catalog_span(7u, middle.x, middle.y) ||
        !ts_catalog_span(10u, middle.z, middle.w) ||
        !ts_catalog_span(8u, high.x, high.y)) return ts_invalid(1u, row, TS_INVALID);
    EvidenceStatus status = ts_admit_catalog_atom(low.x);
    if (status.state != TS_VALID) return status;
    return ts_admit_implementation_head(row);
}

public EvidenceStatus ts_admit_catalog_implementation_members(uint row)
{
    // Complete head coverage precedes both exact/coarse index publication and
    // any early match. Up to 33 admitted roots retain their prior visit budget.
    // Resolving a constant operand charges one substitution step per count
    // projection edge (an array length over a const parameter), so the walk
    // needs the same bounded budget for those steps.
    OwnedConstraintLimits limits = { TS_DEPTH_LIMIT, 0u, 33u * TS_VISIT_LIMIT,
        33u * TS_VISIT_LIMIT };
    return ts_admit_implementation_members(row, limits);
}

public EvidenceStatus ts_admit_catalog_method(uint row)
{
    uint4 method; uint2 tail; uint4 implementation; uint4 span; uint parent;
    if (!ts_catalog_row(10u, row) || !ts_read4(10u, row, 0u, method) ||
        !ts_read2(10u, row, 4u, tail) || !ts_catalog_row(9u, method.x) ||
        !ts_read8(9u, method.x, implementation, span) ||
        !ts_catalog_span(10u, span.z, span.w) || row < span.z || row - span.z >= span.w)
        return ts_invalid(1u, row, 10u);
    if (method.y == TS_INVALID || (method.y & 0xc0000000u) != 0x80000000u ||
        method.w > 3u || tail.y != 0u || !ts_catalog_callable_atom(method.z) ||
        !ts_catalog_row(2u, tail.x) || !ts_owned_identity_matches(method.z, tail.x, 8u, 9u) ||
        !ts_word(2u, tail.x, 3u, parent) || parent != implementation.y)
        return ts_invalid(14u, row, method.x);
    if (row != span.z)
    {
        uint previous;
        if (!ts_word(10u, row - 1u, 1u, previous) || previous >= method.y)
            return ts_invalid(14u, row, row - 1u);
    }
    EvidenceStatus status = ts_admit_inherited_method_environment(tail.x, implementation.y);
    if (status.state != TS_VALID) return status;
    // Exact membership of target atom + owner in accepted Callable records is
    // checked by the catalog index phase; no per-method full-table scan here.
    return ts_ok();
}

public EvidenceStatus ts_admit_catalog_snapshot(uint row)
{
    if (!ts_catalog_row(0u, row)) return ts_invalid(1u, row, 0u);
    if (!ts_snapshot_is_valid(row)) return ts_invalid(2u, row, 0u);
    return ts_ok();
}
public EvidenceStatus ts_admit_catalog_edge(uint row)
{
    if (!ts_catalog_row(6u, row)) return ts_invalid(1u, row, 6u);
    uint2 reference;
    if (!ts_read2(6u, row, 0u, reference) || !ts_catalog_ref(reference))
        return ts_invalid(4u, row, 6u);
    return ts_ok();
}
public EvidenceStatus ts_admit_catalog_root(uint row)
{
    if (!ts_catalog_row(7u, row)) return ts_invalid(1u, row, 7u);
    uint2 reference;
    if (!ts_read2(7u, row, 0u, reference) || !ts_catalog_ref(reference))
        return ts_invalid(4u, row, 7u);
    return ts_ok();
}
