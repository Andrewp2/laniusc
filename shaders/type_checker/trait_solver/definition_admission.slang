// header/required-method set. These checks preserve that accepted relation while
// packing graphs and owners; they do not recreate lexical name resolution.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.graph_admission;
import type_checker.trait_solver.owned_implementation_graph;
import type_checker.owned_type_constraint_contract;

public bool ts_callable_atom_is_valid(uint atom)
{
    uint4 low; uint4 high;
    if (!ts_atom(atom, low, high) || any(high != uint4(0u, 0u, 0u, 0u))) return false;
    if (low.x == 8u) return low.y != TS_INVALID && low.z != TS_INVALID && low.w != TS_INVALID;
    return low.x == 9u && ts_snapshot_is_valid(low.y) && low.z != TS_INVALID && low.w == 0u;
}
public bool ts_owned_identity_matches(uint atom, uint owner, uint public_kind, uint private_kind)
{
    uint4 identity; uint4 extra; uint4 owner_row; uint4 snapshot;
    if (!ts_atom(atom, identity, extra) ||
        !ts_read4(2u, owner, 0u, owner_row) || !ts_read4(0u, owner_row.y, 0u, snapshot)) return false;
    if (identity.x == public_kind)
        return identity.y == snapshot.x && identity.z == snapshot.y && identity.w != TS_INVALID &&
            all(extra == uint4(0u, 0u, 0u, 0u));
    if (identity.x != private_kind || identity.y != owner_row.y || identity.z == TS_INVALID ||
        any(extra != uint4(0u, 0u, 0u, 0u))) return false;
    if (private_kind == 7u) return identity.z == owner_row.z && identity.w == 0u;
    if (private_kind == 9u) return identity.w == 0u;
    return private_kind == 11u && identity.w != TS_INVALID;
}

public SolverStatus ts_admit_callable(uint callable)
{
    uint4 row; uint reverse_callable;
    if (!ts_read4(4u, callable, 0u, row) || !ts_callable_atom_is_valid(row.x) ||
        !ts_owned_identity_matches(row.x, row.y, 8u, 9u) ||
        !ts_word(2u, row.y, 8u, reverse_callable) || reverse_callable != callable)
        return ts_invalid(14u, callable, TS_INVALID);
    uint types; uint constants;
    SolverStatus result = ts_admitted_owner_parameter_counts(row.y, types, constants);
    if (result.state != TS_VALID) return result;
    if (row.z != types || row.w != constants) return ts_invalid(9u, callable, row.y);
    return ts_ok();
}

public SolverStatus ts_admit_inherited_method_environment(uint method_owner, uint implementation_owner)
{
    uint4 owner; uint4 span;
    if (!ts_read_admitted_owner(method_owner, owner, span) || owner.w != implementation_owner)
        return ts_invalid(3u, method_owner, implementation_owner);
    // An exact parent plus an empty own header means the admitted lexical
    // environment is precisely the implementation's environment. Both catalog
    // row admission and implementation admission use this same boundary.
    // Own trait-method parameters and prerequisites need required-member
    // substitution/equivalence and remain explicitly unsupported at this stage.
    if (span.y != 0u || span.w != 0u)
    {
        SolverStatus result = ts_invalid(span.y != 0u ? 11u : 12u, method_owner, implementation_owner);
        result.state = TS_UNSUPPORTED; return result;
    }
    return ts_ok();
}

public SolverStatus ts_admit_goal_roots(
    uint subject, uint first_argument, uint argument_count, uint owner, bool closed)
{
    if (argument_count > 32u) return ts_limit(19u, subject, argument_count, 32u);
    if ((argument_count == 0u && first_argument != 0u) ||
        !ts_row_span(7u, first_argument, argument_count)) return ts_invalid(1u, subject, first_argument);
    uint2 ref;
    if (!ts_read_root(subject, ref) || !ts_admitted_type_reference_shape(ref)) return ts_invalid(4u, subject, TS_INVALID);
    // Ordinal 0 is the subject root; ordinal i > 0 is ordered operand i - 1.
    [loop]
    for (uint ordinal = 0u; ordinal <= argument_count; ordinal++)
    {
        // Independent visits/depth budget for every ordered operand.
        uint visits;
        SolverStatus result = ts_admit_catalog_definition_root(
            ordinal == 0u ? subject : first_argument + ordinal - 1u, owner, closed, visits);
        if (result.state != TS_VALID) return result;
    }
    return ts_ok();
}

public SolverStatus ts_admit_predicate(uint predicate)
{
    uint4 low; uint4 high;
    if (!ts_read8(8u, predicate, low, high) ||
        !ts_nominal_is_valid(low.z) || high.z != 0u || high.w != 0u ||
        !ts_owned_identity_matches(low.x, low.y, 10u, 11u)) return ts_invalid(2u, predicate, TS_INVALID);
    // The completed owner/parameter stages already proved the lexical chain.
    // This predicate still has to belong to that owner's exact predicate span.
    uint4 owner;
    if (!ts_read4(2u, low.y, 4u, owner) || predicate < owner.z || predicate - owner.z >= owner.w)
        return ts_invalid(3u, predicate, low.y);
    return ts_admit_goal_roots(low.w, high.x, high.y, low.y, false);
}

// The caller runs these only in the owned-solver pipeline, paired with the
// complete coarse index, two-sided coherence and retained proof admission.
// Implementation admission is two dispatches split at head coverage: the
// head (row shape, owner, prerequisites, ancestors, goal roots), then its
// members (coverage, required methods). The members dispatch runs only while
// the catalog is still building, so every implementation has passed its head.
public SolverStatus ts_admit_implementation_head(uint implementation)
{
    uint4 low; uint4 middle; uint4 high;
    if (!ts_read8(9u, implementation, low, middle) ||
        !ts_read4(9u, implementation, 8u, high) || high.w != 0u ||
        !ts_nominal_is_valid(low.z) || !ts_owned_identity_matches(low.x, low.y, 6u, 7u))
        return ts_invalid(2u, implementation, TS_INVALID);
    uint types; uint constants;
    SolverStatus result = ts_admitted_owner_parameter_counts(low.y, types, constants);
    if (result.state != TS_VALID) return result;
    // No new flag interpretation is introduced. Parameter inventory comes
    // from exact admitted Owner/Parameter rows, not an unsupported flag bit.
    if (high.z != 0u)
    {
        result = ts_invalid(11u, implementation, low.y); result.state = TS_UNSUPPORTED; return result;
    }
    if ((high.y == 0u && high.x != 0u) || !ts_row_span(8u, high.x, high.y))
        return ts_invalid(1u, implementation, high.x);
    if ((middle.w == 0u && middle.z != 0u) || !ts_row_span(10u, middle.z, middle.w))
        return ts_invalid(1u, implementation, middle.z);

    uint4 owner; uint4 owner_span;
    if (!ts_read_admitted_owner(low.y, owner, owner_span) ||
        high.x != owner_span.z || high.y != owner_span.w)
        return ts_invalid(3u, implementation, low.y);
    // The selected implementation owns its complete prerequisite span. An
    // omitted member, borrowed span, or composed ancestor span is not a proof
    // of the implementation's declared contract. Predicate rows already passed
    // their full identity/shape/visibility admission in the preceding stage.
    [loop]
    for (uint i = 0u; i < high.y; i++)
    {
        uint4 predicate;
        if (!ts_read4(8u, high.x + i, 0u, predicate) || predicate.y != low.y)
            return ts_invalid(3u, implementation, high.x + i);
    }
    // This capability quantifies only the selected owner's own header. Until
    // inherited implementation constraints have an explicit instantiation
    // contract, do not accept them as rigid foreign atoms in matching.
    uint ancestor = owner.w;
    [loop]
    for (uint depth = 1u; ancestor != TS_INVALID; depth++)
    {
        if (depth == TS_DEPTH_LIMIT)
            return ts_limit(6u, low.y, TS_DEPTH_LIMIT + 1u, TS_DEPTH_LIMIT);
        uint4 ancestor_owner; uint4 ancestor_span;
        if (!ts_read_admitted_owner(ancestor, ancestor_owner, ancestor_span))
            return ts_invalid(3u, implementation, ancestor);
        if (ancestor_span.y != 0u || ancestor_span.w != 0u)
        {
            result = ts_invalid(ancestor_span.y != 0u ? 11u : 12u, implementation, ancestor);
            result.state = TS_UNSUPPORTED; return result;
        }
        ancestor = ancestor_owner.w;
    }

    return ts_admit_goal_roots(low.w, middle.x, middle.y, low.y,
        types == 0u && constants == 0u);
}

public SolverStatus ts_admit_implementation_members(uint implementation, OwnedConstraintLimits limits)
{
    // The head passed, so this row reads exactly as it did there.
    uint4 low; uint4 middle;
    if (!ts_read8(9u, implementation, low, middle)) return ts_invalid(2u, implementation, TS_INVALID);
    // Every admitted definition, including an unused/disjoint implementation,
    // must cover every own type and constant parameter in its complete head.
    // Candidate matching/coherence may return early only after this pass.
    SolverStatus result = ts_admit_implementation_coverage(implementation, limits);
    if (result.state != TS_VALID) return result;
    // Host sorts exact required symbols (no semantic matching). The accepted
    // source/export producer owns completeness; strict order preserves uniqueness
    // in one linear pass without an additional arbitrary method-count limit.
    uint previous_required = TS_INVALID;
    [loop]
    for (uint i = 0u; i < middle.w; i++)
    {
        uint row = middle.z + i; uint4 method; uint2 tail; uint parent;
        if (!ts_read4(10u, row, 0u, method) || !ts_read2(10u, row, 4u, tail) ||
            method.x != implementation || method.y == TS_INVALID ||
            (method.y & 0xc0000000u) != 0x80000000u || method.w > 3u || tail.y != 0u ||
            (i != 0u && method.y <= previous_required) ||
            !ts_callable_atom_is_valid(method.z) || !ts_owned_identity_matches(method.z, tail.x, 8u, 9u) ||
            !ts_word(2u, tail.x, 3u, parent) || parent != low.y)
            return ts_invalid(14u, implementation, row);
        previous_required = method.y;
        result = ts_admit_inherited_method_environment(tail.x, low.y);
        if (result.state != TS_VALID) return result;
    }
    return ts_ok();
}
