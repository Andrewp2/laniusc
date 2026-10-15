import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.replay_validation;
import type_checker.program_evidence.obligation_selection;
import type_checker.program_evidence.goal_operations;
import type_checker.program_evidence.proof_store_lifecycle;

public void pev_batch_validate_evidence(uint local)
{
    if (!pev_batch_is_building()) return;
    uint count; uint row;
    if (!pev_table_count(17u, count) || !pev_dispatch_row(local, count, row)) return;
    pev_batch_failure(pev_validate_retained_evidence(row));
}
public void pev_batch_validate_contexts(uint local)
{
    if (!pev_batch_is_building()) return;
    uint count; uint row;
    if (!pev_table_count(13u, count) || !pev_dispatch_row(local, count, row)) return;
    EvidenceStatus status;
    if (pev_bind_scratch(local, row, status)) status = pev_validate_context(row);
    pev_write_status(2u, row, status);
    pev_batch_failure(status);
}
public void pev_batch_index_assumptions(uint local)
{
    if (!pev_batch_is_building()) return;
    uint count; uint row;
    if (!pev_table_count(14u, count) || !pev_dispatch_row(local, count, row)) return;
    EvidenceStatus status;
    if (pev_bind_scratch(local, row, status)) status = pev_build_assumption_index(row);
    pev_batch_failure(status);
}
void pev_call_status(uint call, uint state, uint detail, uint failed, uint required, uint available)
{
    pev_output_write8(4u, call, uint4(state, detail, call, failed),
        uint4(required, available, 0u, 0u));
}
public void pev_batch_reduce_calls(uint local)
{
    if (!pev_batch_is_building()) return;
    uint count; uint call;
    if (!pev_table_count(15u, count) || !pev_dispatch_row(local, count, call)) return;
    uint4 low; uint4 high;
    if (!pev_read4(15u, call, 0u, low) || !pev_read4(15u, call, 4u, high))
    { pev_batch_failure(pev_invalid(1u, call, 15u)); return; }
    bool hypothesis = false;
    for (uint i = 0u; i < high.z; i++)
    {
        uint obligation = high.y + i; uint state; uint detail; uint required; uint available;
        if (!pev_output_read(3u, obligation, 0u, state) ||
            !pev_output_read(3u, obligation, 1u, detail) ||
            !pev_output_read(3u, obligation, 5u, required) || !pev_output_read(3u, obligation, 6u, available))
        { pev_call_status(call, 4u, 1u, obligation, 0u, 0u); pev_batch_failure(pev_invalid(1u, call, obligation)); return; }
        if (state != 1u && state != 2u)
        {
            // Selection failures retain their exact per-obligation result. A
            // missing/unprocessed selector result is an orchestration failure.
            bool terminal = state >= 3u && state <= 7u;
            pev_call_status(call, terminal ? 3u : 4u, terminal ? detail : 15u,
                obligation, required, available);
            EvidenceStatus failed = pev_invalid(terminal ? detail : 15u, call, obligation);
            if (terminal) failed.state = PEV_OBLIGATION_FAILURE;
            pev_batch_failure(failed); return;
        }
        hypothesis = hypothesis || state == 2u;
    }
    bool closed = false; EvidenceStatus status;
    if (pev_bind_scratch(local, call, status)) status = pev_environment_is_closed(high.x, low.z, closed);
    if (status.state != PEV_VALID)
    {
        uint state = status.state == PEV_RESOURCE_LIMIT ? 5u : (status.state == PEV_UNSUPPORTED ? 6u : 4u);
        pev_call_status(call, state, status.detail, PEV_INVALID, status.required, status.available);
        pev_batch_failure(status); return;
    }
    uint caller_owner; bool replay_context;
    if (!pev_context_goal_scope(low.x, caller_owner, replay_context))
    {
        pev_call_status(call, 4u, 3u, PEV_INVALID, 0u, 0u);
        pev_batch_failure(pev_invalid(3u, call, low.x)); return;
    }
    if (replay_context && !closed)
    {
        // A concrete replay's fresh bindings must already reflect its body
        // substitutions, even for zero predicates or unused callee parameters.
        // Retaining the selected body's symbolic parameter is a producer error,
        // not a checked symbolic call that may authorize this replay batch.
        pev_call_status(call, 4u, 10u, PEV_INVALID, 0u, 0u);
        pev_batch_failure(pev_invalid(10u, call, high.x)); return;
    }
    pev_call_status(call, closed && !hypothesis ? 1u : 2u, 0u, PEV_INVALID, 0u, 0u);
}
public void pev_batch_finish()
{
    // Host has covered every required new table/context/obligation/call row,
    // completed each phase, and inserted all required barriers. Any failed row
    // has already replaced BUILDING. No-call batches still require this gate.
    if (!pev_batch_is_building()) return;
    EvidenceStatus accepted = pps_accept_submission();
    if (accepted.state != PEV_VALID) { pps_store_failure(accepted); return; }
    pev_write_batch_receipt(accepted);
}
