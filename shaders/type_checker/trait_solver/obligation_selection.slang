import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.goal_operations;
import type_checker.scoped_type_hash;

uint ts_assumption_bucket_hash(uint context, uint goal_hash)
{ return scoped_type_hash_mix(goal_hash, context); }

public EvidenceStatus ts_build_assumption_index(uint assumption)
{
    uint4 row; uint owner; bool closed; uint context_state;
    if (!ts_read4(14u, assumption, 0u, row) ||
        !ts_context_goal_scope(row.x, owner, closed) ||
        !ts_output_read(2u, row.x, 0u, context_state) || context_state != TS_VALID)
        return ts_invalid(3u, assumption, TS_INVALID);
    EvidenceGoal goal; uint hash;
    if (!ts_predicate_goal(row.y, row.z, owner, goal)) return ts_invalid(1u, assumption, row.y);
    EvidenceStatus status = ts_admit_and_hash_goal(goal, closed, hash);
    if (status.state != TS_VALID) return status;
    uint assumptions; uint buckets; uint arena; uint address;
    if (!ts_table_count(14u, assumptions) || assumption >= assumptions ||
        !ts_bucket_count(assumptions, buckets) ||
        !ts_output_address(9u, ts_assumption_bucket_hash(row.x, hash) & (buckets - 1u), 0u, arena, address) || arena != 1u)
        return ts_invalid(1u, assumption, 9u);
    ts_output_write(8u, assumption, 0u, hash);
    ts_output_write(8u, assumption, 2u, assumption);
    ts_output_write(8u, assumption, 3u, 1u);
    // Every row is inserted once: new suffix only, or all active rows after a
    // full clear. Retained heads may cause the first INVALID expectation to
    // miss, so bound by TOTAL active assumptions, never only the appended delta.
    // Each later miss observes a distinct new head; there is no removal/ABA.
    uint expected = TS_INVALID;
    [loop]
    for (uint attempt = 0u; attempt < assumptions; attempt++)
    {
        uint previous;
        InterlockedCompareExchange(trait_solver_output[address], expected, assumption, previous);
        if (previous == expected)
        {
            ts_output_write(8u, assumption, 1u, previous);
            // Readers wait until every appended/rebuilt insertion and barrier.
            return ts_ok();
        }
        expected = previous;
    }
    return ts_limit(8u, assumption, assumptions + 1u, assumptions);
}
