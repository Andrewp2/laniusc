// header/required-method set. These checks preserve that accepted relation while
// packing graphs and owners; they do not recreate lexical name resolution.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.graph_admission;

public bool pev_callable_atom_is_valid(uint atom)
{
    uint4 low; uint4 high;
    if (!pev_atom(atom, low, high) || any(high != uint4(0u, 0u, 0u, 0u))) return false;
    if (low.x == 8u) return low.y != PEV_INVALID && low.z != PEV_INVALID && low.w != PEV_INVALID;
    return low.x == 9u && pev_snapshot_is_valid(low.y) && low.z != PEV_INVALID && low.w == 0u;
}
public bool pev_owned_identity_matches(uint atom, uint owner, uint public_kind, uint private_kind)
{
    uint4 identity; uint4 extra; uint4 owner_row; uint4 snapshot;
    if (!pev_atom(atom, identity, extra) ||
        !pev_read4(2u, owner, 0u, owner_row) || !pev_read4(0u, owner_row.y, 0u, snapshot)) return false;
    if (identity.x == public_kind)
        return identity.y == snapshot.x && identity.z == snapshot.y && identity.w != PEV_INVALID &&
            all(extra == uint4(0u, 0u, 0u, 0u));
    if (identity.x != private_kind || identity.y != owner_row.y || identity.z == PEV_INVALID ||
        any(extra != uint4(0u, 0u, 0u, 0u))) return false;
    if (private_kind == 7u) return identity.z == owner_row.z && identity.w == 0u;
    if (private_kind == 9u) return identity.w == 0u;
    return private_kind == 11u && identity.w != PEV_INVALID;
}

public EvidenceStatus pev_admit_callable(uint callable)
{
    uint4 row; uint reverse_callable;
    if (!pev_read4(4u, callable, 0u, row) || !pev_callable_atom_is_valid(row.x) ||
        !pev_owned_identity_matches(row.x, row.y, 8u, 9u) ||
        !pev_word(2u, row.y, 8u, reverse_callable) || reverse_callable != callable)
        return pev_invalid(14u, callable, PEV_INVALID);
    uint types; uint constants;
    EvidenceStatus result = pev_admit_owner_chain(row.y, types, constants);
    if (result.state != PEV_VALID) return result;
    if (row.z != types || row.w != constants) return pev_invalid(9u, callable, row.y);
    return pev_ok();
}

public EvidenceStatus pev_admit_goal_roots(
    uint subject, uint first_argument, uint argument_count, uint owner, bool closed)
{
    if (argument_count > 32u) return pev_limit(19u, subject, argument_count, 32u);
    if ((argument_count == 0u && first_argument != 0u) ||
        !pev_row_span(7u, first_argument, argument_count)) return pev_invalid(1u, subject, first_argument);
    uint2 ref;
    if (!pev_read_root(subject, ref) || !pev_type_reference_shape(ref)) return pev_invalid(4u, subject, PEV_INVALID);
    uint visits;
    EvidenceStatus result = pev_admit_root(subject, PEV_INVALID, owner, closed, visits);
    if (result.state != PEV_VALID) return result;
    for (uint i = 0u; i < argument_count; i++)
    {
        // Independent visits/depth budget for every ordered operand.
        result = pev_admit_root(first_argument + i, PEV_INVALID, owner, closed, visits);
        if (result.state != PEV_VALID) return result;
    }
    return pev_ok();
}

public EvidenceStatus pev_admit_predicate(uint predicate)
{
    uint4 low; uint4 high;
    if (!pev_read4(8u, predicate, 0u, low) || !pev_read4(8u, predicate, 4u, high) ||
        !pev_nominal_is_valid(low.z) || high.z != 0u || high.w != 0u ||
        !pev_owned_identity_matches(low.x, low.y, 10u, 11u)) return pev_invalid(2u, predicate, PEV_INVALID);
    uint types; uint constants;
    EvidenceStatus result = pev_admit_owner_chain(low.y, types, constants);
    if (result.state != PEV_VALID) return result;
    uint4 owner;
    if (!pev_read4(2u, low.y, 4u, owner) || predicate < owner.z || predicate - owner.z >= owner.w)
        return pev_invalid(3u, predicate, low.y);
    return pev_admit_goal_roots(low.w, high.x, high.y, low.y, false);
}

public EvidenceStatus pev_admit_implementation(uint implementation)
{
    uint4 low; uint4 middle; uint4 high;
    if (!pev_read4(9u, implementation, 0u, low) || !pev_read4(9u, implementation, 4u, middle) ||
        !pev_read4(9u, implementation, 8u, high) || high.w != 0u ||
        !pev_nominal_is_valid(low.z) || !pev_owned_identity_matches(low.x, low.y, 6u, 7u))
        return pev_invalid(2u, implementation, PEV_INVALID);
    uint types; uint constants;
    EvidenceStatus result = pev_admit_owner_chain(low.y, types, constants);
    if (result.state != PEV_VALID) return result;
    if (high.z != 0u || types != 0u || constants != 0u)
    {
        result = pev_invalid(11u, implementation, low.y); result.state = PEV_UNSUPPORTED; return result;
    }
    if (high.y != 0u)
    {
        result = pev_invalid(12u, implementation, high.x); result.state = PEV_UNSUPPORTED; return result;
    }
    if (high.x != 0u || (middle.w == 0u && middle.z != 0u) || !pev_row_span(10u, middle.z, middle.w))
        return pev_invalid(1u, implementation, middle.z);
    result = pev_admit_goal_roots(low.w, middle.x, middle.y, low.y, true);
    if (result.state != PEV_VALID) return result;
    // Host sorts exact required symbols (no semantic matching). The accepted
    // source/export producer owns completeness; strict order preserves uniqueness
    // in one linear pass without an additional arbitrary method-count limit.
    uint previous_required = PEV_INVALID;
    for (uint i = 0u; i < middle.w; i++)
    {
        uint row = middle.z + i; uint4 method; uint2 tail; uint parent;
        if (!pev_read4(10u, row, 0u, method) || !pev_read2(10u, row, 4u, tail) ||
            method.x != implementation || method.y == PEV_INVALID ||
            (method.y & 0xc0000000u) != 0x80000000u || method.w > 3u || tail.y != 0u ||
            (i != 0u && method.y <= previous_required) ||
            !pev_callable_atom_is_valid(method.z) || !pev_owned_identity_matches(method.z, tail.x, 8u, 9u) ||
            !pev_word(2u, tail.x, 3u, parent) || parent != low.y)
            return pev_invalid(14u, implementation, row);
        previous_required = method.y;
        uint method_types; uint method_constants;
        result = pev_admit_owner_chain(tail.x, method_types, method_constants);
        if (result.state != PEV_VALID) return result;
        if (method_types != 0u || method_constants != 0u)
        {
            result = pev_invalid(11u, implementation, tail.x); result.state = PEV_UNSUPPORTED; return result;
        }
    }
    return pev_ok();
}
