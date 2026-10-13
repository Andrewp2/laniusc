import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.goal_operations;
import type_checker.scoped_type_hash;

uint pev_assumption_bucket_hash(uint context, uint goal_hash)
{ return scoped_type_hash_mix(goal_hash, context); }

public EvidenceStatus pev_build_assumption_index(uint assumption)
{
    uint4 row; uint owner; bool closed; uint context_state;
    if (!pev_read4(14u, assumption, 0u, row) ||
        !pev_context_goal_scope(row.x, owner, closed) ||
        !pev_output_read(2u, row.x, 0u, context_state) || context_state != PEV_VALID)
        return pev_invalid(3u, assumption, PEV_INVALID);
    EvidenceGoal goal; uint hash;
    if (!pev_predicate_goal(row.y, row.z, owner, goal)) return pev_invalid(1u, assumption, row.y);
    EvidenceStatus status = pev_admit_and_hash_goal(goal, closed, hash);
    if (status.state != PEV_VALID) return status;
    uint assumptions; uint buckets; uint arena; uint address;
    if (!pev_table_count(14u, assumptions) || assumption >= assumptions ||
        !pev_bucket_count(assumptions, buckets) ||
        !pev_output_address(9u, pev_assumption_bucket_hash(row.x, hash) & (buckets - 1u), 0u, arena, address) || arena != 1u)
        return pev_invalid(1u, assumption, 9u);
    pev_output_write(8u, assumption, 0u, hash);
    pev_output_write(8u, assumption, 2u, assumption);
    pev_output_write(8u, assumption, 3u, 1u);
    // Every row is inserted once: new suffix only, or all active rows after a
    // full clear. Retained heads may cause the first INVALID expectation to
    // miss, so bound by TOTAL active assumptions, never only the appended delta.
    // Each later miss observes a distinct new head; there is no removal/ABA.
    uint expected = PEV_INVALID;
    [loop]
    for (uint attempt = 0u; attempt < assumptions; attempt++)
    {
        uint previous;
        InterlockedCompareExchange(program_evidence_output[address], expected, assumption, previous);
        if (previous == expected)
        {
            pev_output_write(8u, assumption, 1u, previous);
            // Readers wait until every appended/rebuilt insertion and barrier.
            return pev_ok();
        }
        expected = previous;
    }
    return pev_limit(8u, assumption, assumptions + 1u, assumptions);
}
