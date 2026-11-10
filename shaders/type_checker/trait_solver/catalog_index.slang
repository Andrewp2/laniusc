import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.owned_implementation_graph;
import type_checker.owned_type_constraint_contract;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_scratch;

public uint ts_atom_hash(uint row)
{
    uint hash = 2166136261u;
    for (uint field = 0u; field < 8u; field++)
    {
        uint value;
        if (!ts_word(1u, row, field, value)) return 0u;
        hash = scoped_type_hash_mix(hash, value);
    }
    return hash;
}
public bool ts_atom_keys_equal(uint left, uint right)
{
    for (uint field = 0u; field < 8u; field++)
    {
        uint a; uint b;
        if (!ts_word(1u, left, field, a) || !ts_word(1u, right, field, b) || a != b) return false;
    }
    return true;
}
public SolverStatus ts_hash_admitted_catalog_root(uint root, out uint hash)
{
    hash = 0u; uint2 ref; uint nodes; uint atoms;
    if (!ts_read_root(root, ref) || !ts_catalog_count(5u, nodes) || !ts_catalog_count(1u, atoms))
        return ts_invalid(1u, root, TS_INVALID);
    // All catalog rows and every owning implementation goal were admitted in
    // an earlier dispatch. No per-candidate preflight is repeated here.
    if (!scoped_type_ref_hash_scratch<CatalogTraitSolverTypeGraph>(ref.x, ref.y, TS_INVALID, nodes, atoms, hash))
        return ts_invalid(15u, root, TS_INVALID);
    return ts_ok();
}
public SolverStatus ts_hash_admitted_implementation(uint implementation, out uint hash)
{
    hash = 0u; uint4 low; uint4 args;
    if (!ts_read4(9u, implementation, 0u, low) || !ts_read4(9u, implementation, 4u, args))
        return ts_invalid(1u, implementation, TS_INVALID);
    // The subject root (ordinal 0) and each argument root share one hash site.
    uint mixed = scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, low.z), args.y);
    [loop]
    for (uint ordinal = 0u; ordinal <= args.y; ordinal++)
    {
        uint child_hash;
        SolverStatus status = ts_hash_admitted_catalog_root(
            ordinal == 0u ? low.w : args.x + ordinal - 1u, child_hash);
        if (status.state != TS_VALID) return status;
        mixed = scoped_type_hash_mix(mixed, child_hash);
    }
    hash = mixed;
    return ts_ok();
}
public bool ts_equal_admitted_catalog_roots(uint left_root, uint right_root)
{
    uint2 left; uint2 right; uint nodes; uint atoms;
    if (!ts_read_root(left_root, left) || !ts_read_root(right_root, right) ||
        !ts_catalog_count(5u, nodes) || !ts_catalog_count(1u, atoms)) return false;
    return scoped_type_refs_equal_scratch<CatalogTraitSolverTypeGraph>(
        left.x, left.y, TS_INVALID, right.x, right.y, TS_INVALID, nodes, atoms);
}
public bool ts_equal_admitted_implementation_keys(uint left, uint right)
{
    uint4 a; uint4 b; uint4 aa; uint4 ba;
    if (!ts_read4(9u, left, 0u, a) || !ts_read4(9u, right, 0u, b) ||
        !ts_read4(9u, left, 4u, aa) || !ts_read4(9u, right, 4u, ba) ||
        a.z != b.z || aa.y != ba.y || !ts_equal_admitted_catalog_roots(a.w, b.w)) return false;
    for (uint i = 0u; i < aa.y; i++)
        if (!ts_equal_admitted_catalog_roots(aa.x + i, ba.x + i)) return false;
    return true;
}
// Coarse keys select every potentially overlapping head. They are never proof
// of applicability: trait identity, ordered operands and subject are matched by
// the owned structural engine after complete definition admission.
public uint ts_coarse_implementation_hash(uint trait_atom, uint argument_count)
{
    return scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, trait_atom), argument_count);
}
public SolverStatus ts_hash_coarse_implementation(uint implementation, out uint hash)
{
    hash = 0u; uint4 low; uint4 args;
    if (!ts_read4(9u, implementation, 0u, low) || !ts_read4(9u, implementation, 4u, args) ||
        args.y > 32u) return ts_invalid(1u, implementation, TS_INVALID);
    hash = ts_coarse_implementation_hash(low.z, args.y);
    return ts_ok();
}
public SolverStatus ts_exact_implementation_eligible(uint implementation, out bool eligible)
{
    eligible = false; uint4 low; uint4 high; uint4 owner; uint4 owner_span;
    if (!ts_read4(9u, implementation, 0u, low) || !ts_read4(9u, implementation, 8u, high) ||
        !ts_read_admitted_owner(low.y, owner, owner_span))
        return ts_invalid(1u, implementation, TS_INVALID);
    // Catalog admission rejects all inherited parameter/predicate scopes and
    // admits the complete head. Empty own inventory therefore means closed.
    // Conditional closed heads also stay off the unconditional exact fast path.
    eligible = owner_span.y == 0u && high.y == 0u;
    return ts_ok();
}

// Publication returns its failure; the caller owns its stage's one catalog
// failure report site.
SolverStatus ts_publish_catalog_index(uint index_table, uint bucket_table,
    uint row, uint hash, uint admitted_row, uint rows, uint buckets)
{
    if (row >= rows || buckets == 0u) return ts_invalid(1u, row, index_table);
    uint arena; uint address;
    if (!ts_output_address(bucket_table, hash & (buckets - 1u), 0u, arena, address) || arena != 0u ||
        !ts_output_write(index_table, row, 0u, hash) ||
        !ts_output_write(index_table, row, 2u, admitted_row) ||
        !ts_output_write(index_table, row, 3u, 1u))
        return ts_invalid(1u, row, bucket_table);
    // Lookup never overlaps this dispatch. A barrier before readers ensures
    // every head/link is complete even when the CAS publishes the head first.
    // Each row inserts once; an initial miss may observe a prior chunk's head,
    // and each later miss observes a distinct new insertion. No removal/ABA.
    // CAS retains the workaround for Slang2026.2's InterlockedExchange lowering.
    uint expected = TS_INVALID;
    [loop]
    for (uint attempt = 0u; attempt < rows; attempt++)
    {
        uint previous;
        InterlockedCompareExchange(trait_solver_catalog[address], expected, row, previous);
        if (previous == expected)
        {
            if (!ts_output_write(index_table, row, 1u, previous))
                return ts_invalid(1u, row, index_table);
            return ts_ok();
        }
        expected = previous;
    }
    return ts_limit(8u, row, rows + 1u, rows);
}
public void ts_publish_index(uint row, uint hash, uint admitted_row)
{
    uint rows; uint buckets;
    SolverStatus status = ts_invalid(1u, row, 6u);
    if (ts_work_counts(rows, buckets))
        status = ts_publish_catalog_index(6u, 7u, row, hash, admitted_row, rows, buckets);
    ts_catalog_failure(status);
}
// Index 0 is the coarse implementation index, index 1 the exact one.
public SolverStatus ts_publish_implementation_index(uint implementation, uint index, uint hash)
{
    bool coarse = index == 0u;
    uint catalog_rows = 0u; uint work_rows; uint buckets;
    bool counted = ts_work_counts(work_rows, buckets);
    if (coarse) counted = ts_catalog_count(9u, catalog_rows) && counted;
    if (!counted) return ts_invalid(1u, implementation, coarse ? 11u : 6u);
    return ts_publish_catalog_index(coarse ? 11u : 6u, coarse ? 12u : 7u, implementation, hash,
        implementation, coarse ? catalog_rows : work_rows, buckets);
}

public SolverStatus ts_check_atom_unique(uint atom)
{
    uint atom_count; uint rows; uint buckets; uint hash; uint candidate;
    if (!ts_catalog_count(1u, atom_count) || atom >= atom_count || !ts_work_counts(rows, buckets) ||
        !ts_output_read(6u, atom, 0u, hash) || !ts_output_read(7u, hash & (buckets - 1u), 0u, candidate))
        return ts_invalid(1u, atom, TS_INVALID);
    uint examined = 0u;
    for (; candidate != TS_INVALID; examined++)
    {
        if (examined == TS_CHAIN_LIMIT) return ts_limit(8u, atom, examined + 1u, TS_CHAIN_LIMIT);
        if (candidate >= atom_count) return ts_invalid(1u, atom, candidate);
        uint other_hash; uint next; uint admitted;
        if (!ts_output_read(6u, candidate, 0u, other_hash) || !ts_output_read(6u, candidate, 1u, next) ||
            !ts_output_read(6u, candidate, 3u, admitted) || admitted != 1u)
            return ts_invalid(1u, atom, candidate);
        if (candidate != atom && hash == other_hash && ts_atom_keys_equal(atom, candidate))
            return ts_invalid(16u, atom, candidate);
        candidate = next;
    }
    return ts_ok();
}

public SolverStatus ts_check_impl_coherence(uint implementation)
{
    uint implementation_count; uint rows; uint buckets; uint candidate; uint4 own_index;
    if (!ts_catalog_count(9u, implementation_count) || implementation >= implementation_count ||
        !ts_work_counts(rows, buckets) || !ts_output_read4(11u, implementation, 0u, own_index) ||
        own_index.z != implementation || own_index.w != 1u ||
        !ts_output_read(12u, own_index.x & (buckets - 1u), 0u, candidate))
        return ts_invalid(1u, implementation, TS_INVALID);
    OwnedConstraintLimits limits = { TS_DEPTH_LIMIT, TS_VISIT_LIMIT,
        TS_VISIT_LIMIT, TS_VISIT_LIMIT };
    uint examined = 0u;
    [loop]
    for (; candidate != TS_INVALID; examined++)
    {
        if (examined == TS_CHAIN_LIMIT) return ts_limit(8u, implementation, examined + 1u, TS_CHAIN_LIMIT);
        if (candidate >= implementation_count) return ts_invalid(1u, implementation, candidate);
        uint4 other;
        if (!ts_output_read4(11u, candidate, 0u, other) || other.z != candidate || other.w != 1u)
            return ts_invalid(1u, implementation, candidate);
        // Every unordered pair is checked once. Head shape/coverage admission
        // finished before the index was built, so NoMatch may return early.
        if (candidate < implementation && own_index.x == other.x)
        {
            bool overlap;
            SolverStatus status = ts_implementation_heads_overlap(implementation, candidate, limits, overlap);
            if (status.state != TS_VALID) return status;
            if (overlap)
            {
                uint left_identity; uint right_identity;
                if (!ts_word(9u, implementation, 0u, left_identity) || !ts_word(9u, candidate, 0u, right_identity))
                    return ts_invalid(1u, implementation, candidate);
                // Duplicate identity rejection still runs independently in the
                // earlier atom-map phase, including different/disjoint heads.
                status = ts_invalid(16u, implementation, candidate);
                if (left_identity != right_identity)
                { status.state = TS_COHERENCE_CONFLICT; status.detail = 0u; }
                return status;
            }
        }
        candidate = other.y;
    }
    return ts_ok();
}
