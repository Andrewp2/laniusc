import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.owned_implementation_graph;
import type_checker.owned_type_constraint_contract;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;

public uint pev_atom_hash(uint row)
{
    uint hash = 2166136261u;
    for (uint field = 0u; field < 8u; field++)
    {
        uint value;
        if (!pev_word(1u, row, field, value)) return 0u;
        hash = scoped_type_hash_mix(hash, value);
    }
    return hash;
}
public bool pev_atom_keys_equal(uint left, uint right)
{
    for (uint field = 0u; field < 8u; field++)
    {
        uint a; uint b;
        if (!pev_word(1u, left, field, a) || !pev_word(1u, right, field, b) || a != b) return false;
    }
    return true;
}
public EvidenceStatus pev_hash_admitted_catalog_root(uint root, out uint hash)
{
    hash = 0u; uint2 ref; uint nodes; uint atoms;
    if (!pev_read_root(root, ref) || !pev_catalog_count(5u, nodes) || !pev_catalog_count(1u, atoms))
        return pev_invalid(1u, root, PEV_INVALID);
    // All catalog rows and every owning implementation goal were admitted in
    // an earlier dispatch. No per-candidate preflight is repeated here.
    if (!scoped_type_ref_hash<CatalogProgramEvidenceTypeGraph>(ref.x, ref.y, PEV_INVALID, nodes, atoms, hash))
        return pev_invalid(15u, root, PEV_INVALID);
    return pev_ok();
}
public EvidenceStatus pev_hash_admitted_implementation(uint implementation, out uint hash)
{
    hash = 0u; uint4 low; uint4 args;
    if (!pev_read4(9u, implementation, 0u, low) || !pev_read4(9u, implementation, 4u, args))
        return pev_invalid(1u, implementation, PEV_INVALID);
    uint subject_hash;
    EvidenceStatus status = pev_hash_admitted_catalog_root(low.w, subject_hash);
    if (status.state != PEV_VALID) return status;
    hash = scoped_type_hash_mix(2166136261u, low.z);
    hash = scoped_type_hash_mix(hash, args.y);
    hash = scoped_type_hash_mix(hash, subject_hash);
    for (uint argument = 0u; argument < args.y; argument++)
    {
        uint child_hash;
        status = pev_hash_admitted_catalog_root(args.x + argument, child_hash);
        if (status.state != PEV_VALID) return status;
        hash = scoped_type_hash_mix(hash, child_hash);
    }
    return pev_ok();
}
public bool pev_equal_admitted_catalog_roots(uint left_root, uint right_root)
{
    uint2 left; uint2 right; uint nodes; uint atoms;
    if (!pev_read_root(left_root, left) || !pev_read_root(right_root, right) ||
        !pev_catalog_count(5u, nodes) || !pev_catalog_count(1u, atoms)) return false;
    return scoped_type_refs_equal<CatalogProgramEvidenceTypeGraph>(
        left.x, left.y, PEV_INVALID, right.x, right.y, PEV_INVALID, nodes, atoms);
}
public bool pev_equal_admitted_implementation_keys(uint left, uint right)
{
    uint4 a; uint4 b; uint4 aa; uint4 ba;
    if (!pev_read4(9u, left, 0u, a) || !pev_read4(9u, right, 0u, b) ||
        !pev_read4(9u, left, 4u, aa) || !pev_read4(9u, right, 4u, ba) ||
        a.z != b.z || aa.y != ba.y || !pev_equal_admitted_catalog_roots(a.w, b.w)) return false;
    for (uint i = 0u; i < aa.y; i++)
        if (!pev_equal_admitted_catalog_roots(aa.x + i, ba.x + i)) return false;
    return true;
}
// Coarse keys select every potentially overlapping head. They are never proof
// of applicability: trait identity, ordered operands and subject are matched by
// the owned structural engine after complete definition admission.
public uint pev_coarse_implementation_hash(uint trait_atom, uint argument_count)
{
    return scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, trait_atom), argument_count);
}
public EvidenceStatus pev_hash_coarse_implementation(uint implementation, out uint hash)
{
    hash = 0u; uint4 low; uint4 args;
    if (!pev_read4(9u, implementation, 0u, low) || !pev_read4(9u, implementation, 4u, args) ||
        args.y > 32u) return pev_invalid(1u, implementation, PEV_INVALID);
    hash = pev_coarse_implementation_hash(low.z, args.y);
    return pev_ok();
}
public EvidenceStatus pev_exact_implementation_eligible(uint implementation, out bool eligible)
{
    eligible = false; uint4 low; uint4 high; uint4 owner; uint4 owner_span;
    if (!pev_read4(9u, implementation, 0u, low) || !pev_read4(9u, implementation, 8u, high) ||
        !pev_read_admitted_owner(low.y, owner, owner_span))
        return pev_invalid(1u, implementation, PEV_INVALID);
    // Catalog admission rejects all inherited parameter/predicate scopes and
    // admits the complete head. Empty own inventory therefore means closed.
    // Conditional closed heads also stay off the unconditional exact fast path.
    eligible = owner_span.y == 0u && high.y == 0u;
    return pev_ok();
}

void pev_publish_catalog_index(uint index_table, uint bucket_table,
    uint row, uint hash, uint admitted_row, uint rows, uint buckets)
{
    if (row >= rows || buckets == 0u) { pev_catalog_failure(pev_invalid(1u, row, index_table)); return; }
    uint arena; uint address;
    if (!pev_output_address(bucket_table, hash & (buckets - 1u), 0u, arena, address) || arena != 0u ||
        !pev_output_write(index_table, row, 0u, hash) ||
        !pev_output_write(index_table, row, 2u, admitted_row) ||
        !pev_output_write(index_table, row, 3u, 1u))
    { pev_catalog_failure(pev_invalid(1u, row, bucket_table)); return; }
    // Lookup never overlaps this dispatch. A barrier before readers ensures
    // every head/link is complete even when the CAS publishes the head first.
    // Each row inserts once; an initial miss may observe a prior chunk's head,
    // and each later miss observes a distinct new insertion. No removal/ABA.
    // CAS retains the workaround for Slang2026.2's InterlockedExchange lowering.
    uint expected = PEV_INVALID;
    [loop]
    for (uint attempt = 0u; attempt < rows; attempt++)
    {
        uint previous;
        InterlockedCompareExchange(program_evidence_catalog[address], expected, row, previous);
        if (previous == expected)
        {
            if (!pev_output_write(index_table, row, 1u, previous))
                pev_catalog_failure(pev_invalid(1u, row, index_table));
            return;
        }
        expected = previous;
    }
    pev_catalog_failure(pev_limit(8u, row, rows + 1u, rows));
}
public void pev_publish_index(uint row, uint hash, uint admitted_row)
{
    uint rows; uint buckets;
    if (!pev_work_counts(rows, buckets)) { pev_catalog_failure(pev_invalid(1u, row, 6u)); return; }
    pev_publish_catalog_index(6u, 7u, row, hash, admitted_row, rows, buckets);
}
public void pev_publish_coarse_implementation(uint implementation, uint hash)
{
    uint rows; uint work_rows; uint buckets;
    if (!pev_catalog_count(9u, rows) || !pev_work_counts(work_rows, buckets))
    { pev_catalog_failure(pev_invalid(1u, implementation, 11u)); return; }
    pev_publish_catalog_index(11u, 12u, implementation, hash, implementation, rows, buckets);
}

public EvidenceStatus pev_check_atom_unique(uint atom)
{
    uint atom_count; uint rows; uint buckets; uint hash; uint candidate;
    if (!pev_catalog_count(1u, atom_count) || atom >= atom_count || !pev_work_counts(rows, buckets) ||
        !pev_output_read(6u, atom, 0u, hash) || !pev_output_read(7u, hash & (buckets - 1u), 0u, candidate))
        return pev_invalid(1u, atom, PEV_INVALID);
    uint examined = 0u;
    for (; candidate != PEV_INVALID; examined++)
    {
        if (examined == PEV_CHAIN_LIMIT) return pev_limit(8u, atom, examined + 1u, PEV_CHAIN_LIMIT);
        if (candidate >= atom_count) return pev_invalid(1u, atom, candidate);
        uint other_hash; uint next; uint admitted;
        if (!pev_output_read(6u, candidate, 0u, other_hash) || !pev_output_read(6u, candidate, 1u, next) ||
            !pev_output_read(6u, candidate, 3u, admitted) || admitted != 1u)
            return pev_invalid(1u, atom, candidate);
        if (candidate != atom && hash == other_hash && pev_atom_keys_equal(atom, candidate))
            return pev_invalid(16u, atom, candidate);
        candidate = next;
    }
    return pev_ok();
}

public EvidenceStatus pev_check_impl_coherence(uint implementation)
{
    uint implementation_count; uint rows; uint buckets; uint candidate; uint4 own_index;
    if (!pev_catalog_count(9u, implementation_count) || implementation >= implementation_count ||
        !pev_work_counts(rows, buckets) || !pev_output_read4(11u, implementation, 0u, own_index) ||
        own_index.z != implementation || own_index.w != 1u ||
        !pev_output_read(12u, own_index.x & (buckets - 1u), 0u, candidate))
        return pev_invalid(1u, implementation, PEV_INVALID);
    OwnedConstraintLimits limits = { PEV_DEPTH_LIMIT, PEV_VISIT_LIMIT,
        PEV_VISIT_LIMIT, PEV_VISIT_LIMIT };
    uint examined = 0u;
    [loop]
    for (; candidate != PEV_INVALID; examined++)
    {
        if (examined == PEV_CHAIN_LIMIT) return pev_limit(8u, implementation, examined + 1u, PEV_CHAIN_LIMIT);
        if (candidate >= implementation_count) return pev_invalid(1u, implementation, candidate);
        uint4 other;
        if (!pev_output_read4(11u, candidate, 0u, other) || other.z != candidate || other.w != 1u)
            return pev_invalid(1u, implementation, candidate);
        // Every unordered pair is checked once. Head shape/coverage admission
        // finished before the index was built, so NoMatch may return early.
        if (candidate < implementation && own_index.x == other.x)
        {
            bool overlap;
            EvidenceStatus status = pev_implementation_heads_overlap(implementation, candidate, limits, overlap);
            if (status.state != PEV_VALID) return status;
            if (overlap)
            {
                uint left_identity; uint right_identity;
                if (!pev_word(9u, implementation, 0u, left_identity) || !pev_word(9u, candidate, 0u, right_identity))
                    return pev_invalid(1u, implementation, candidate);
                // Duplicate identity rejection still runs independently in the
                // earlier atom-map phase, including different/disjoint heads.
                status = pev_invalid(16u, implementation, candidate);
                if (left_identity != right_identity)
                { status.state = PEV_COHERENCE_CONFLICT; status.detail = 0u; }
                return status;
            }
        }
        candidate = other.y;
    }
    return pev_ok();
}
