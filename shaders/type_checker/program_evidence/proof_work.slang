// Transient frontier records never become retained proof identities. They may
// be updated only by their owning stage; every stage transition is separated by
// a dispatch barrier. Persistent proof readers cannot read these records.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_scratch;

public static const uint PPS_WORK_REQUEST = 0u;
public static const uint PPS_WORK_NORMALIZED = 1u;
public static const uint PPS_WORK_NEW = 2u;
public static const uint PPS_WORK_ALIAS = 3u;
public static const uint PPS_WORK_WAITING = 4u;
public static const uint PPS_WORK_READY = 5u;
public static const uint PPS_WORK_PROOF_PENDING = 6u;
public static const uint PPS_WORK_PROVEN = 7u;
public static const uint PPS_WORK_MISSING = 8u;
public static const uint PPS_WORK_NOTIFIED = 9u;
// Normalization owns these intermediate states. Only the final commit stage
// changes GOAL_VALIDATED to NORMALIZED; failures leave the wave unpublished.
public static const uint PPS_WORK_NORMALIZATION_EMITTED = 20u;
public static const uint PPS_WORK_NORMALIZATION_VALIDATED = 21u;
public static const uint PPS_WORK_GOAL_VALIDATED = 22u;
public static const uint PPS_ATOMIC_ATTEMPTS = 65536u;
public static const uint PPS_LOGICAL_WORK_LIMIT = 65536u;

public bool pps_pending4(uint table, uint row, uint field, out uint4 value)
{
    value = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID);
    uint address;
    if (!pps_address(table, row, field, 4u, true, address)) return false;
    value = uint4(program_evidence_proof_store[address], program_evidence_proof_store[address + 1u],
        program_evidence_proof_store[address + 2u], program_evidence_proof_store[address + 3u]);
    return true;
}
public bool pps_work_read(uint row, out uint4 key, out uint4 selection,
    out uint4 completion, out uint4 source)
{
    return pps_read4(PPS_WORK, row, 0u, key) &&
        pps_read4(PPS_WORK, row, 4u, selection) &&
        pps_read4(PPS_WORK, row, 8u, completion) &&
        pps_read4(PPS_WORK, row, 12u, source);
}
public bool pps_write4(uint table, uint row, uint field, uint4 value)
{
    uint address;
    if (!pps_address(table, row, field, 4u, true, address)) return false;
    program_evidence_proof_store[address] = value.x;
    program_evidence_proof_store[address + 1u] = value.y;
    program_evidence_proof_store[address + 2u] = value.z;
    program_evidence_proof_store[address + 3u] = value.w;
    return true;
}
public bool pps_work_write(uint row, uint4 key, uint4 selection, uint4 completion, uint4 source)
{
    return pps_write4(PPS_WORK, row, 0u, key) && pps_write4(PPS_WORK, row, 4u, selection) &&
        pps_write4(PPS_WORK, row, 8u, completion) && pps_write4(PPS_WORK, row, 12u, source);
}
public bool pps_transient_word(uint table, uint row, uint field, uint value)
{
    uint address;
    if (table < PPS_PERSISTENT_TABLES || !pps_address(table, row, field, 1u, true, address)) return false;
    program_evidence_proof_store[address] = value; return true;
}

// A successful CAS is a prefix reservation, not admission. Each emitter first
// counts its complete rows and makes one reservation per table; overflow never
// truncates a row. A failed wave discards its entire unaccepted suffix.
public EvidenceStatus pps_reserve(uint table, uint count, uint subject, out uint first)
{
    first = PEV_INVALID;
    uint4 span; uint accepted;
    if (!pps_building() || !pev_batch_is_building() || !pps_descriptor(table, span, accepted))
        return pev_invalid(66u, subject, table);
    if (count == 0u) { first = 0u; return pev_ok(); }
    uint address = PPS_DIRECTORY + table * 6u + 1u;
    uint expected = span.y;
    [loop]
    for (uint attempt = 0u; attempt < PPS_ATOMIC_ATTEMPTS; attempt++)
    {
        uint limit = table == PPS_WORK ? PPS_LOGICAL_WORK_LIMIT :
            (table == PPS_REDUCTION_QUEUE ? 2u * PPS_LOGICAL_WORK_LIMIT : PEV_INVALID);
        if (expected > limit || count > limit - expected)
            return pev_limit(72u, table,
                count > PEV_INVALID - expected ? PEV_INVALID : expected + count, limit);
        if (expected > span.z || count > span.z - expected || count >= PEV_INVALID - expected)
            return pev_limit(69u, table,
                count > PEV_INVALID - expected ? PEV_INVALID : expected + count, span.z);
        uint previous;
        InterlockedCompareExchange(program_evidence_proof_store[address], expected, expected + count, previous);
        if (previous == expected) { first = expected; return pev_ok(); }
        expected = previous;
    }
    return pev_limit(8u, subject, PPS_ATOMIC_ATTEMPTS + 1u, PPS_ATOMIC_ATTEMPTS);
}

public bool pps_goal_equal(uint left, uint right)
{
    uint4 a; uint4 aa; uint4 b; uint4 ba; uint nodes; uint atoms;
    if (!pps_read8(PPS_GOALS, left, a, aa) || !pps_read8(PPS_GOALS, right, b, ba) ||
        a.x != b.x || aa.x != ba.x || aa.x > 32u ||
        !pps_count(PPS_TERM_NODES, nodes) || !pev_table_count(1u, atoms)) return false;
    [loop]
    for (uint i = 0u; i <= aa.x; i++)
    {
        uint2 l = a.yz; uint2 r = b.yz;
        if (i != 0u && (!pps_read2(PPS_TERM_ROOTS, a.w + i - 1u, 0u, l) ||
            !pps_read2(PPS_TERM_ROOTS, b.w + i - 1u, 0u, r))) return false;
        if (!scoped_type_refs_equal_scratch<SolverProofTermGraph>(l.x, l.y, PEV_INVALID,
            r.x, r.y, PEV_INVALID, nodes, atoms)) return false;
    }
    return true;
}

public EvidenceStatus pps_insert_work(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source; uint4 goal; uint4 extra;
    uint4 buckets; uint unused; uint active;
    if (!pps_work_read(work, key, selected, completion, source) || key.z != PPS_WORK_NORMALIZED ||
        !pps_read8(PPS_GOALS, key.y, goal, extra) || !pps_count(PPS_WORK, active) ||
        !pps_descriptor(PPS_GOAL_BUCKETS, buckets, unused) || buckets.w == 0u ||
        (buckets.w & (buckets.w - 1u)) != 0u || !pps_span(PPS_GOAL_INDEX, work, 1u))
        return pev_invalid(70u, work, PPS_GOAL_INDEX);
    uint hash = scoped_type_hash_mix(extra.y, key.x);
    uint address;
    if (!pps_address(PPS_GOAL_BUCKETS, hash & (buckets.w - 1u), 0u, 1u, true, address) ||
        !pps_write4(PPS_GOAL_INDEX, work, 0u, uint4(hash, PEV_INVALID, work, 1u)))
        return pev_invalid(1u, work, PPS_GOAL_INDEX);
    uint expected = PEV_INVALID;
    [loop]
    for (uint attempt = 0u; attempt < active; attempt++)
    {
        uint previous;
        InterlockedCompareExchange(program_evidence_proof_store[address], expected, work, previous);
        if (previous == expected)
        {
            if (!pps_transient_word(PPS_GOAL_INDEX, work, 1u, previous))
                return pev_invalid(1u, work, PPS_GOAL_INDEX);
            return pev_ok();
        }
        expected = previous;
    }
    return pev_limit(8u, work, active + 1u, active);
}

// Resolve only after the whole insertion dispatch. All candidate goals were
// independently admitted. Lowest logical Work ID gives a stable representative
// across waves; repeated goals become edges, never optimistic recursive proofs.
public EvidenceStatus pps_resolve_work(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source; uint4 index;
    uint4 buckets; uint unused; uint active; uint address;
    if (!pps_work_read(work, key, selected, completion, source) || key.z != PPS_WORK_NORMALIZED ||
        !pps_read4(PPS_GOAL_INDEX, work, 0u, index) || index.z != work || index.w != 1u ||
        !pps_count(PPS_WORK, active) || !pps_descriptor(PPS_GOAL_BUCKETS, buckets, unused) ||
        buckets.w == 0u || (buckets.w & (buckets.w - 1u)) != 0u ||
        !pps_address(PPS_GOAL_BUCKETS, index.x & (buckets.w - 1u), 0u, 1u, false, address))
        return pev_invalid(70u, work, PPS_GOAL_INDEX);
    uint candidate = program_evidence_proof_store[address]; uint best = work;
    [loop]
    for (uint examined = 0u; candidate != PEV_INVALID; examined++)
    {
        if (examined == PEV_CHAIN_LIMIT) return pev_limit(8u, work, examined + 1u, PEV_CHAIN_LIMIT);
        uint4 link; uint4 other;
        if (candidate >= active || !pps_read4(PPS_GOAL_INDEX, candidate, 0u, link) ||
            link.z != candidate || link.w != 1u || !pps_read4(PPS_WORK, candidate, 0u, other))
            return pev_invalid(70u, work, candidate);
        if (link.x == index.x && other.x == key.x && candidate < best &&
            pps_goal_equal(key.y, other.y)) best = candidate;
        candidate = link.y;
    }
    key.z = best == work ? PPS_WORK_NEW : PPS_WORK_ALIAS; key.w = best;
    return pps_write4(PPS_WORK, work, 0u, key) ? pev_ok() : pev_invalid(1u, work, PPS_WORK);
}
