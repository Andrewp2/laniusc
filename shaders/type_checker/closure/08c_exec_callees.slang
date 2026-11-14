// Callers of rejected entries (instance_exec.slang): one lane per table
// entry, after selection (08_exec_select, 08a_exec_members) and before the
// layout. A pending entry that calls a rejected table entry is rejected too:
// its copy calls each selected callee's copy directly (09_exec_rows), and a
// rejected callee has no copy. Each run moves a rejection at least one
// caller up; the pass runs EXEC_CALLEE_ROUNDS times
// (instance_closure_passes.rs). A caller still pending after the last run
// names its rejected callee's template, as before.
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;
import type_checker.closure.instance_exec;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint entry = dtid.x + dtid.y * 16776960u;
    uint entries = min(min(instance_table_counts[IT_COUNT_ENTRIES], IT_RANK_LIMIT), ex_entry_capacity());
    if (entry >= entries || ex_quad(entry, EX_Q_HEAD).x != EX_PENDING) return;
    uint4 key = instance_table[2u * entry];
    for (uint offset = 0u; offset < key.y; offset++)
    {
        uint2 call = instance_row_calls[key.w + offset];
        if (call.x == IT_CALL_ENTRY && call.y < entries &&
            ex_quad(call.y, EX_Q_HEAD).x >= EX_REJECT_TABLE)
        {
            ex_set_quad(entry, EX_Q_HEAD, uint4(EX_REJECT_CALL, 0u, 0u, 0u));
            return;
        }
    }
}
