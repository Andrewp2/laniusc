// Admit every catalog row and reduce all failures before publishing a catalog.
// These local prefix checks establish immutable transitive closure only after
// that barrier. A valid individual row is not a whole-catalog certificate.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.definition_admission;

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
    return reference.y != PEV_INVALID && (reference.x == 0x80000001u ||
        (reference.x == 0x80000002u && pev_catalog_parameter(reference.y, true)));
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
    EvidenceStatus status = pev_admit_catalog_owner(parameter.x);
    if (status.state != PEV_VALID) return status;
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
    return pev_admit_implementation(row);
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
    uint types; uint constants;
    EvidenceStatus status = pev_admit_owner_chain(tail.x, types, constants);
    if (status.state != PEV_VALID) return status;
    if (types != 0u || constants != 0u)
    {
        status = pev_invalid(11u, row, tail.x); status.state = PEV_UNSUPPORTED; return status;
    }
    // Exact membership of target atom + owner in accepted Callable records is
    // checked by the catalog index phase; no per-method full-table scan here.
    return pev_ok();
}

public EvidenceStatus pev_admit_catalog_row(uint table, uint row)
{
    if (table > 10u || !pev_catalog_row(table, row)) return pev_invalid(1u, row, table);
    switch (table)
    {
    case 0u:
        if (!pev_snapshot_is_valid(row)) return pev_invalid(2u, row, table);
        return pev_ok();
    case 1u: return pev_admit_catalog_atom(row);
    case 2u: return pev_admit_catalog_owner(row);
    case 3u: return pev_admit_catalog_parameter(row);
    case 4u: return pev_admit_catalog_callable(row);
    case 5u: return pev_admit_catalog_node(row);
    case 6u: case 7u:
    {
        uint2 reference;
        if (!pev_read2(table, row, 0u, reference) || !pev_catalog_ref(reference))
            return pev_invalid(4u, row, table);
        return pev_ok();
    }
    case 8u: return pev_admit_catalog_predicate(row);
    case 9u: return pev_admit_catalog_implementation(row);
    case 10u: return pev_admit_catalog_method(row);
    default: return pev_invalid(1u, row, table);
    }
}
