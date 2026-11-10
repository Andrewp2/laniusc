import type_checker.trait_solver.constant_atoms;
// Scratch only. This phase requires an admitted frozen catalog, immutable input
// rows, and a failure-reduction barrier over EVERY batch suffix row. A VALID row
// is not a proof receipt. Context/evidence goal matching and concrete origin-call
// status validation remain mandatory subsequent phases owned by the selector.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.checked_graph_operations;
import type_checker.trait_solver.catalog_row_admission;
import type_checker.trait_solver.definition_admission;
import type_checker.trait_solver.proof_goal_equality;

// Frozen host provenance supplies the exact accepted call_hir -> actual owner
// inventory and public-unit registry. Packet equality checks below preserve it;
// they do not reconstruct lexical source ownership from a numeric HIR row.
public bool ts_batch_row(uint table, uint row)
{
    SolverTable desc;
    return ts_descriptor(table, desc) && row >= desc.catalog_count &&
        row - desc.catalog_count < desc.batch_count;
}
public bool ts_batch_span(uint table, uint first, uint count)
{
    SolverTable desc;
    if (!ts_descriptor(table, desc)) return false;
    if (count == 0u) return first == 0u;
    return first >= desc.catalog_count &&
        first - desc.catalog_count <= desc.batch_count &&
        count <= desc.batch_count - (first - desc.catalog_count);
}

public SolverStatus ts_applicable_predicate_count(uint owner, out uint count)
{
    count = 0u;
    uint original = owner;
    for (uint depth = 0u; owner != TS_INVALID; depth++)
    {
        if (depth == TS_DEPTH_LIMIT) return ts_limit(6u, original, depth + 1u, TS_DEPTH_LIMIT);
        if (ts_owner_chain_contains(original, depth, owner)) return ts_invalid(5u, original, owner);
        uint4 low; uint4 high;
        if (!ts_catalog_row(2u, owner) || !ts_read4(2u, owner, 0u, low) ||
            !ts_read4(2u, owner, 4u, high) || !ts_catalog_span(8u, high.z, high.w))
            return ts_invalid(3u, original, owner);
        if (high.w >= TS_INVALID - count) return ts_limit(19u, original, TS_INVALID, TS_INVALID - 1u);
        count += high.w;
        owner = low.w;
    }
    return ts_ok();
}
[ForceInline]
public SolverStatus ts_applicable_predicate_at(uint owner, uint ordinal, out uint predicate)
{
    uint count;
    return ts_applicable_predicate_lookup(owner, ordinal, false, count, predicate);
}
// The applicable predicate count, then (unless count_only) the predicate at
// ordinal. Both uses share one count site.
public SolverStatus ts_applicable_predicate_lookup(uint owner, uint ordinal, bool count_only,
    out uint count, out uint predicate)
{
    predicate = TS_INVALID;
    SolverStatus status = ts_applicable_predicate_count(owner, count);
    if (status.state != TS_VALID || count_only) return status;
    if (ordinal >= count) return ts_invalid(22u, owner, ordinal);
    for (uint depth = 0u; depth < TS_DEPTH_LIMIT && owner != TS_INVALID; depth++)
    {
        uint4 low; uint4 high;
        if (!ts_read4(2u, owner, 0u, low) || !ts_read4(2u, owner, 4u, high))
            return ts_invalid(1u, owner, TS_INVALID);
        if (ordinal < high.w)
        {
            predicate = high.z + ordinal;
            uint actual_owner;
            if (!ts_word(8u, predicate, 1u, actual_owner) || actual_owner != owner)
                return ts_invalid(3u, predicate, owner);
            return ts_ok();
        }
        ordinal -= high.w;
        owner = low.w;
    }
    return ts_invalid(3u, owner, ordinal);
}

public SolverStatus ts_admit_batch_atom(uint atom)
{
    uint4 low; uint4 high;
    if (!ts_batch_row(1u, atom) || !ts_atom(atom, low, high)) return ts_invalid(1u, atom, 1u);
    bool valid = false;
    switch (low.x)
    {
    case 1u: case 2u: valid = ts_nominal_is_valid(atom); break;
    case 3u: case 4u: valid = ts_binder_is_valid(atom); break;
    case 5u:
        if (low.z > 1u) return ts_invalid(4u, atom, low.z);
        valid = low.y < atom && ts_parameter_is_valid(atom, low.z == 1u); break;
    case 6u: case 10u:
        valid = low.y != TS_INVALID && low.z != TS_INVALID && low.w != TS_INVALID &&
            all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 7u:
        valid = ts_snapshot_is_valid(low.y) && low.z != TS_INVALID && low.w == 0u &&
            all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 8u: case 9u: valid = ts_callable_atom_is_valid(atom); break;
    case 11u:
        valid = ts_snapshot_is_valid(low.y) && low.z != TS_INVALID && low.w != TS_INVALID &&
            all(high == uint4(0u, 0u, 0u, 0u)); break;
    case 12u:
    { uint3 value; valid = ts_constant_atom_value(atom, value); break; }
    default: return ts_invalid(2u, atom, low.x);
    }
    if (!valid) return ts_invalid(2u, atom, low.x);
    // Exact tuple uniqueness across catalog and suffix is an interning/index
    // precondition; shape validation alone is not an identity uniqueness proof.
    return ts_ok();
}
public SolverStatus ts_admit_batch_node(uint node)
{
    uint4 low; uint4 high;
    if (!ts_batch_row(5u, node) || !ts_read4(5u, node, 0u, low) ||
        !ts_read4(5u, node, 4u, high)) return ts_invalid(1u, node, 5u);
    if (low.x == 1u && low.w > 32u) return ts_limit(19u, node, low.w, 32u);
    if (!ts_node_is_valid(node)) return ts_invalid(4u, node, TS_INVALID);
    if (low.x == 1u)
    {
        for (uint i = 0u; i < low.w; i++)
        {
            uint2 child;
            if (!ts_read2(6u, low.z + i, 0u, child)) return ts_invalid(1u, node, low.z + i);
            if ((child.x == 3u || child.x == 0x80000003u) && child.y >= node) return ts_invalid(5u, node, child.y);
        }
    }
    else if ((high.x == 3u || high.x == 0x80000003u) && high.y >= node) return ts_invalid(5u, node, high.y);
    if (low.x == 2u && high.z == 0x80000003u && high.w >= node) return ts_invalid(5u, node, high.w);
    // The append-only producer emits children before parents. This local rule
    // rejects cycles even in unused suffix nodes. Owned binding roots also get
    // complete depth/work/domain/visibility admission through their environment.
    return ts_ok();
}

// Header helpers validate local relations without calling each other recursively
// through full environment/assumption/obligation admission.
public SolverStatus ts_batch_context_header(uint context, out uint4 low, out uint4 high)
{
    low = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID);
    high = low;
    if (!ts_batch_row(13u, context) || !ts_read4(13u, context, 0u, low) ||
        !ts_read4(13u, context, 4u, high) || !ts_catalog_row(0u, low.x) ||
        !ts_snapshot_is_valid(low.x) || !ts_batch_span(14u, low.w, high.x))
        return ts_invalid(1u, context, 13u);
    // Word 7: 0 = hard context, 1 = soft (a refuted obligation demotes its
    // calls instead of failing the batch, ts_batch_reduce_calls).
    if (high.w > 1u) return ts_invalid(21u, context, 13u);
    if (high.y > 2u) return ts_invalid(4u, context, high.y);
    if (high.y == 2u)
    {
        if (low.y != TS_INVALID || low.z != TS_INVALID || low.w != 0u ||
            high.x != 0u || high.z != TS_INVALID) return ts_invalid(3u, context, low.y);
        return ts_ok();
    }
    uint4 owner; uint callable; uint4 target;
    if (!ts_catalog_row(2u, low.y) || !ts_read4(2u, low.y, 0u, owner) || owner.y != low.x ||
        !ts_word(2u, low.y, 8u, callable) || !ts_catalog_row(4u, callable) ||
        !ts_read4(4u, callable, 0u, target) || target.y != low.y)
        return ts_invalid(14u, context, low.y);
    if (high.y == 0u)
    {
        if (low.z != TS_INVALID || high.z != TS_INVALID) return ts_invalid(3u, context, low.z);
        return ts_ok();
    }
    uint4 environment; uint environment_owner; uint4 origin; uint4 callee;
    if (!ts_batch_row(11u, low.z) || !ts_read4(11u, low.z, 0u, environment) ||
        !ts_word(11u, low.z, 4u, environment_owner) || environment_owner != context ||
        environment.x != low.y || environment.w != 0u ||
        !ts_batch_row(15u, high.z) || !ts_read4(15u, high.z, 0u, origin) ||
        origin.x >= context || !ts_catalog_row(4u, origin.w) ||
        !ts_read4(4u, origin.w, 0u, callee) || callee.y != low.y)
        return ts_invalid(3u, context, high.z);
    // Strict context order follows prior-admission, append-only host production.
    // The subsequent replay phase must additionally require CHECKED_CONCRETE
    // for origin_call; merely naming an earlier Call does not supply that proof.
    return ts_ok();
}
// A call row checks its own fields and then its context row; a context row
// checks only itself. Both reach ts_batch_context_header at one site.
public SolverStatus ts_batch_owner_header(uint row, bool is_call, out uint4 low, out uint4 high)
{
    low = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID);
    high = low;
    uint context_row = row;
    if (is_call)
    {
        if (!ts_batch_row(15u, row) || !ts_read4(15u, row, 0u, low) ||
            !ts_read4(15u, row, 4u, high) || low.y == TS_INVALID ||
            !ts_catalog_row(4u, low.w) || !ts_batch_span(16u, high.y, high.z))
            return ts_invalid(1u, row, 15u);
        if (high.w != 0u) return ts_invalid(21u, row, 15u);
        context_row = low.x;
    }
    uint4 context; uint4 extra;
    SolverStatus status = ts_batch_context_header(context_row, context, extra);
    if (!is_call) { low = context; high = extra; return status; }
    if (status.state != TS_VALID) return status;
    uint call = row;
    if (low.z != context.y) return ts_invalid(3u, call, low.z);
    uint4 callee; uint4 environment; uint environment_owner;
    if (!ts_read4(4u, low.w, 0u, callee) || !ts_batch_row(11u, high.x) ||
        !ts_read4(11u, high.x, 0u, environment) || !ts_word(11u, high.x, 4u, environment_owner) ||
        environment_owner != call || environment.w != 1u || environment.x != callee.y)
        return ts_invalid(3u, call, high.x);
    return ts_ok();
}
[ForceInline]
public SolverStatus ts_batch_call_header(uint call, out uint4 low, out uint4 high)
{
    return ts_batch_owner_header(call, true, low, high);
}

public SolverStatus ts_admit_batch_environment(uint environment, uint owner_kind, uint owner_row)
{
    uint4 env; uint backlink;
    if (!ts_batch_row(11u, environment) || !ts_read4(11u, environment, 0u, env) ||
        !ts_word(11u, environment, 4u, backlink)) return ts_invalid(1u, environment, 11u);
    if (owner_kind > 1u || env.w != owner_kind || backlink != owner_row)
        return ts_invalid(3u, environment, owner_row);
    // Step 0 reads the owning call or context and admits the environment once.
    // A context owner then reads its origin call at step 1 through the same
    // header site; origin_extra holds that call's second row half.
    uint header_row = owner_row; bool header_call = owner_kind == 1u;
    uint4 owner; uint4 origin_extra; SolverStatus status;
    [loop]
    for (uint step = 0u; ; step++)
    {
        uint4 extra;
        status = ts_batch_owner_header(header_row, header_call, owner, extra);
        origin_extra = extra;
        if (status.state != TS_VALID || step == 1u) break;
        uint expected_owner; uint caller_owner;
        if (owner_kind == 1u)
        {
            if (extra.x != environment) return ts_invalid(3u, environment, owner_row);
            uint4 callee;
            if (!ts_read4(4u, owner.w, 0u, callee)) return ts_invalid(14u, environment, owner.w);
            expected_owner = callee.y; caller_owner = owner.z;
        }
        else
        {
            if (extra.y != 1u || owner.z != environment) return ts_invalid(3u, environment, owner_row);
            expected_owner = owner.y; caller_owner = owner.y;
        }
        status = ts_admit_environment(environment, expected_owner, caller_owner, owner_kind);
        if (status.state != TS_VALID || owner_kind == 1u) return status;
        header_row = extra.z; header_call = true;
    }
    if (status.state != TS_VALID) return status;
    uint4 source;
    if (!ts_read4(11u, origin_extra.x, 0u, source) || source.x != env.x || source.w != 1u ||
        source.z != env.z || !ts_batch_span(12u, source.y, source.z))
        return ts_invalid(9u, environment, origin_extra.x);
    // The host creates body bindings by copying every exact (parameter, root)
    // from the immutable origin call. Check that whole copy, including bindings
    // unused by predicates. This is a row-identity relation, not type equality.
    for (uint i = 0u; i < env.z; i++)
    {
        uint4 a; uint4 b;
        if (!ts_read4(12u, env.y + i, 0u, a) || !ts_read4(12u, source.y + i, 0u, b) ||
            b.x != origin_extra.x || b.w != 0u || a.y != b.y || a.z != b.z)
            return ts_invalid(9u, environment, source.y + i);
    }
    return ts_ok();
}
public SolverStatus ts_admit_batch_binding(uint binding)
{
    uint4 row; uint4 env;
    if (!ts_batch_row(12u, binding) || !ts_read4(12u, binding, 0u, row) ||
        !ts_batch_row(11u, row.x) || !ts_read4(11u, row.x, 0u, env) ||
        !ts_batch_span(12u, env.y, env.z) || binding < env.y || binding - env.y >= env.z)
        return ts_invalid(3u, binding, 12u);
    if (row.w != 0u) return ts_invalid(21u, binding, 12u);
    // Frozen owners/parameters and suffix Atom1/Node5/Edge6/Root7 rows passed
    // complete prior stages. Env11 still owns its full binding/completeness scan;
    // this reverse check preserves exact atom visibility and value domain.
    uint4 parameter; uint2 value;
    if (!ts_read_admitted_parameter(row.y, parameter) || !ts_admitted_parameter_visible(row.y, env.x) ||
        !ts_read_root(row.z, value) ||
        !(parameter.z == 0u ? ts_admitted_type_reference_shape(value) : ts_admitted_constant_reference_shape(value)))
        return ts_invalid(4u, binding, row.y);
    if (parameter.z == 1u && ts_constant_reference_scalar(value) != ts_constant_parameter_scalar(row.y))
        return ts_invalid(4u, binding, row.y);
    // Its owning Env row validates sorting, completeness, actual caller scope,
    // and full root graphs. This reverse span check rejects orphan bindings.
    return ts_ok();
}

// Assumption admission is split around its claimed context's header so a
// context stage can read that header at the same site as its own.
public SolverStatus ts_read_batch_assumption(uint assumption, out uint4 row)
{
    uint2 tail;
    if (!ts_batch_row(14u, assumption) || !ts_read4(14u, assumption, 0u, row) ||
        !ts_read2(14u, assumption, 4u, tail)) return ts_invalid(1u, assumption, 14u);
    if (any(tail != uint2(0u, 0u))) return ts_invalid(21u, assumption, 14u);
    return ts_ok();
}
public SolverStatus ts_admit_batch_assumption(uint assumption)
{
    uint4 row; uint4 context; uint4 extra;
    SolverStatus status = ts_read_batch_assumption(assumption, row);
    if (status.state != TS_VALID) return status;
    status = ts_batch_context_header(row.x, context, extra);
    if (status.state != TS_VALID) return status;
    return ts_admit_batch_assumption_in(assumption, row, context, extra);
}
// The checks that follow the header (context, extra) of the claimed row.x.
public SolverStatus ts_admit_batch_assumption_in(uint assumption, uint4 row,
    uint4 context, uint4 extra)
{
    SolverStatus status;
    if (extra.y == 2u || assumption < context.w || assumption - context.w >= extra.x || row.z != context.z)
        return ts_invalid(3u, assumption, row.x);
    uint predicate;
    status = ts_applicable_predicate_at(context.y, assumption - context.w, predicate);
    if (status.state != TS_VALID) return status;
    if (row.y != predicate) return ts_invalid(3u, assumption, row.y);
    if (extra.y == 0u)
    {
        if (row.w != TS_INVALID) return ts_invalid(3u, assumption, row.w);
        return ts_ok();
    }
    uint4 proof; uint4 provenance; uint4 origin;
    if (!ts_batch_row(17u, row.w) || !ts_read4(17u, row.w, 0u, proof) || proof.x != 1u ||
        !ts_read4(17u, row.w, 4u, provenance) ||
        !ts_batch_row(15u, provenance.y) || !ts_read4(15u, provenance.y, 0u, origin) || origin.x >= row.x)
        return ts_invalid(10u, assumption, row.w);
    uint proof_context;
    if (!pps_retained_proof_reference(proof.w, provenance.x, proof.x, proof_context) ||
        origin.x != proof_context) return ts_invalid(10u, assumption, row.w);
    // Supplied proof may have a different predicate ID and origin call. Its
    // normalized conclusion is compared with this requirement during replay.
    return ts_ok();
}
// Obligation admission is split around its claimed call's header so a call
// stage can read that header at the same site as its own.
public SolverStatus ts_read_batch_obligation(uint obligation, out uint4 row)
{
    if (!ts_batch_row(16u, obligation) || !ts_read4(16u, obligation, 0u, row))
        return ts_invalid(1u, obligation, 16u);
    if (row.w != 0u) return ts_invalid(21u, obligation, 16u);
    return ts_ok();
}
public SolverStatus ts_admit_batch_obligation(uint obligation)
{
    uint4 row; uint4 call; uint4 extra;
    SolverStatus status = ts_read_batch_obligation(obligation, row);
    if (status.state != TS_VALID) return status;
    status = ts_batch_call_header(row.x, call, extra);
    if (status.state != TS_VALID) return status;
    return ts_admit_batch_obligation_in(obligation, row, call, extra);
}
// The checks that follow the header (call, extra) of the claimed row.x:
// the span and callee checks naming the predicate to look up, the lookup,
// then the claimed predicate.
public SolverStatus ts_batch_obligation_predicate(uint obligation, uint4 row,
    uint4 call, uint4 extra, out uint owner, out uint ordinal)
{
    owner = TS_INVALID; ordinal = 0u;
    if (obligation < extra.y || obligation - extra.y >= extra.z || row.z != extra.x)
        return ts_invalid(3u, obligation, row.x);
    uint4 callee;
    if (!ts_read4(4u, call.w, 0u, callee)) return ts_invalid(14u, obligation, call.w);
    owner = callee.y; ordinal = obligation - extra.y;
    return ts_ok();
}
public SolverStatus ts_admit_batch_obligation_in(uint obligation, uint4 row,
    uint4 call, uint4 extra)
{
    uint owner; uint ordinal; uint predicate;
    SolverStatus status = ts_batch_obligation_predicate(obligation, row, call, extra, owner, ordinal);
    if (status.state != TS_VALID) return status;
    status = ts_applicable_predicate_at(owner, ordinal, predicate);
    if (status.state != TS_VALID) return status;
    if (row.y != predicate) return ts_invalid(3u, obligation, row.y);
    return ts_ok();
}
public SolverStatus ts_admit_batch_context(uint context)
{
    // Ordinal 0 reads this context's own header; ordinal i > 0 admits
    // assumption i - 1, whose claimed context header is read at the same site.
    uint4 row = uint4(0u, 0u, 0u, 0u); uint assumptions = 0u;
    [loop]
    for (uint ordinal = 0u; ordinal <= assumptions; ordinal++)
    {
        uint assumption = row.w + ordinal - 1u;
        uint header_row = context; uint4 claim = uint4(0u, 0u, 0u, 0u);
        SolverStatus status;
        if (ordinal != 0u)
        {
            status = ts_read_batch_assumption(assumption, claim);
            if (status.state != TS_VALID) return status;
            header_row = claim.x;
        }
        uint4 header; uint4 extra;
        status = ts_batch_context_header(header_row, header, extra);
        if (status.state != TS_VALID) return status;
        if (ordinal == 0u)
        {
            row = header;
            uint count;
            status = ts_applicable_predicate_count(row.y, count);
            if (status.state != TS_VALID) return status;
            if (count != extra.x) return ts_invalid(22u, context, count);
            if (extra.y == 1u)
            {
                status = ts_admit_batch_environment(row.z, 0u, context);
                if (status.state != TS_VALID) return status;
            }
            assumptions = extra.x;
            continue;
        }
        status = ts_admit_batch_assumption_in(assumption, claim, header, extra);
        if (status.state != TS_VALID) return status;
        uint claimed_context;
        if (!ts_word(14u, assumption, 0u, claimed_context) || claimed_context != context)
            return ts_invalid(3u, context, assumption);
    }
    return ts_ok();
}
public SolverStatus ts_admit_batch_call(uint call)
{
    // Ordinal 0 reads this call's own header; ordinal i > 0 admits obligation
    // i - 1, whose claimed call header is read at the same site.
    uint first_obligation = 0u; uint obligations = 0u;
    [loop]
    for (uint ordinal = 0u; ordinal <= obligations; ordinal++)
    {
        uint obligation = first_obligation + ordinal - 1u;
        uint header_row = call; uint4 claim = uint4(0u, 0u, 0u, 0u);
        SolverStatus status;
        if (ordinal != 0u)
        {
            status = ts_read_batch_obligation(obligation, claim);
            if (status.state != TS_VALID) return status;
            header_row = claim.x;
        }
        uint4 header; uint4 extra;
        status = ts_batch_call_header(header_row, header, extra);
        if (status.state != TS_VALID) return status;
        // The call counts its callee's applicable predicates; an obligation
        // looks up its own predicate. Both share one lookup site.
        uint owner; uint predicate_ordinal = 0u;
        if (ordinal == 0u)
        {
            status = ts_admit_batch_environment(extra.x, 1u, call);
            if (status.state != TS_VALID) return status;
            uint4 callee;
            if (!ts_read4(4u, header.w, 0u, callee)) return ts_invalid(14u, call, header.w);
            owner = callee.y;
        }
        else
        {
            status = ts_batch_obligation_predicate(obligation, claim, header, extra,
                owner, predicate_ordinal);
            if (status.state != TS_VALID) return status;
        }
        uint count; uint predicate;
        status = ts_applicable_predicate_lookup(owner, predicate_ordinal, ordinal == 0u,
            count, predicate);
        if (status.state != TS_VALID) return status;
        if (ordinal == 0u)
        {
            if (count != extra.z) return ts_invalid(22u, call, count);
            first_obligation = extra.y; obligations = extra.z;
            continue;
        }
        if (claim.y != predicate) return ts_invalid(3u, obligation, claim.y);
        uint claimed_call;
        if (!ts_word(16u, obligation, 0u, claimed_call) || claimed_call != call)
            return ts_invalid(3u, call, obligation);
    }
    return ts_ok();
}
public SolverStatus ts_admit_batch_evidence(uint evidence)
{
    uint4 row; uint4 extra;
    if (!ts_batch_row(17u, evidence) || !ts_read4(17u, evidence, 0u, row) ||
        !ts_read4(17u, evidence, 4u, extra)) return ts_invalid(1u, evidence, 17u);
    if (extra.w != 0u) return ts_invalid(21u, evidence, 17u);
    if (row.x != 1u && row.x != 2u) return ts_invalid(4u, evidence, row.x);
    uint4 obligation; uint4 call; uint4 call_extra;
    SolverStatus status = ts_admit_batch_obligation(extra.z);
    if (status.state != TS_VALID) return status;
    if (!ts_read4(16u, extra.z, 0u, obligation) || obligation.x != extra.y ||
        obligation.y != row.y || obligation.z != row.z) return ts_invalid(13u, evidence, extra.z);
    status = ts_batch_call_header(extra.y, call, call_extra);
    if (status.state != TS_VALID) return status;
    if (row.z != call_extra.x) return ts_invalid(13u, evidence, extra.y);
    uint proof_context;
    if (!pps_retained_proof_reference(row.w, extra.x, row.x, proof_context) ||
        proof_context != call.x) return ts_invalid(13u, evidence, row.w);
    // These are representation relationships. Phase13 must still match every
    // word against the exact retained GPU output and check successful source
    // result states. That prior accepted result establishes the witness/goal
    // relation; shape-valid rows naming arbitrary closure roots are not proof.
    return ts_ok();
}
