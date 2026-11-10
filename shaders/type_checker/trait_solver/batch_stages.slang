import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.replay_validation;
import type_checker.trait_solver.obligation_selection;
import type_checker.trait_solver.goal_operations;
import type_checker.trait_solver.proof_store_lifecycle;

public void ts_batch_validate_evidence(uint local)
{
    if (!ts_batch_is_building()) return;
    uint count; uint row;
    if (!ts_table_count(17u, count) || !ts_dispatch_row(local, count, row)) return;
    ts_batch_failure(ts_validate_retained_evidence(row));
}
public void ts_batch_validate_contexts(uint local)
{
    if (!ts_batch_is_building()) return;
    uint count; uint row;
    if (!ts_table_count(13u, count) || !ts_dispatch_row(local, count, row)) return;
    EvidenceStatus status;
    if (ts_bind_scratch(local, row, status)) status = ts_validate_context(row);
    ts_write_status(2u, row, status);
    ts_batch_failure(status);
}
public void ts_batch_index_assumptions(uint local)
{
    if (!ts_batch_is_building()) return;
    uint count; uint row;
    if (!ts_table_count(14u, count) || !ts_dispatch_row(local, count, row)) return;
    EvidenceStatus status;
    if (ts_bind_scratch(local, row, status)) status = ts_build_assumption_index(row);
    ts_batch_failure(status);
}
void ts_call_status(uint call, uint state, uint detail, uint failed, uint required, uint available)
{
    ts_output_write8(4u, call, uint4(state, detail, call, failed),
        uint4(required, available, 0u, 0u));
}
public void ts_batch_reduce_calls(uint local)
{
    if (!ts_batch_is_building()) return;
    uint count; uint call;
    if (!ts_table_count(15u, count) || !ts_dispatch_row(local, count, call)) return;
    uint4 low; uint4 high;
    if (!ts_read4(15u, call, 0u, low) || !ts_read4(15u, call, 4u, high))
    { ts_batch_failure(ts_invalid(1u, call, 15u)); return; }
    // A call of a soft context (context word 7 = 1) whose obligation has no
    // finite derivation (result 3) is refuted: status 8, naming its first such
    // obligation, and the batch goes on. Every other failure stays terminal,
    // and a refuted call still passes the input checks below.
    uint soft_word = 0u;
    bool soft = ts_word(13u, low.x, 7u, soft_word) && soft_word == 1u;
    uint refuted = TS_INVALID; uint refuted_detail = 0u;
    uint refuted_required = 0u; uint refuted_available = 0u;
    bool hypothesis = false;
    for (uint i = 0u; i < high.z; i++)
    {
        uint obligation = high.y + i; uint state; uint detail; uint required; uint available;
        if (!ts_output_read(3u, obligation, 0u, state) ||
            !ts_output_read(3u, obligation, 1u, detail) ||
            !ts_output_read(3u, obligation, 5u, required) || !ts_output_read(3u, obligation, 6u, available))
        { ts_call_status(call, 4u, 1u, obligation, 0u, 0u); ts_batch_failure(ts_invalid(1u, call, obligation)); return; }
        bool soft_refuted = soft && state == 3u;
        if (soft_refuted && refuted == TS_INVALID)
        {
            refuted = obligation; refuted_detail = detail;
            refuted_required = required; refuted_available = available;
        }
        if (!soft_refuted && state != 1u && state != 2u)
        {
            // Selection failures retain their exact per-obligation result. A
            // missing/unprocessed selector result is an orchestration failure.
            bool terminal = state >= 3u && state <= 7u;
            ts_call_status(call, terminal ? 3u : 4u, terminal ? detail : 15u,
                obligation, required, available);
            EvidenceStatus failed = ts_invalid(terminal ? detail : 15u, call, obligation);
            if (terminal) failed.state = TS_OBLIGATION_FAILURE;
            ts_batch_failure(failed); return;
        }
        hypothesis = hypothesis || state == 2u;
    }
    bool closed = false; EvidenceStatus status;
    if (ts_bind_scratch(local, call, status)) status = ts_environment_is_closed(high.x, low.z, closed);
    if (status.state != TS_VALID)
    {
        uint state = status.state == TS_RESOURCE_LIMIT ? 5u : (status.state == TS_UNSUPPORTED ? 6u : 4u);
        ts_call_status(call, state, status.detail, TS_INVALID, status.required, status.available);
        ts_batch_failure(status); return;
    }
    uint caller_owner; bool replay_context;
    if (!ts_context_goal_scope(low.x, caller_owner, replay_context))
    {
        ts_call_status(call, 4u, 3u, TS_INVALID, 0u, 0u);
        ts_batch_failure(ts_invalid(3u, call, low.x)); return;
    }
    if (replay_context && !closed)
    {
        // A concrete replay's fresh bindings must already reflect its body
        // substitutions, even for zero predicates or unused callee parameters.
        // Retaining the selected body's symbolic parameter is a producer error,
        // not a checked symbolic call that may authorize this replay batch.
        ts_call_status(call, 4u, 10u, TS_INVALID, 0u, 0u);
        ts_batch_failure(ts_invalid(10u, call, high.x)); return;
    }
    if (refuted != TS_INVALID)
        ts_call_status(call, 8u, refuted_detail, refuted, refuted_required, refuted_available);
    else
        ts_call_status(call, closed && !hypothesis ? 1u : 2u, 0u, TS_INVALID, 0u, 0u);
}
public void ts_batch_finish()
{
    // Host has covered every required new table/context/obligation/call row,
    // completed each phase, and inserted all required barriers. Any failed row
    // has already replaced BUILDING. No-call batches still require this gate.
    if (!ts_batch_is_building()) return;
    EvidenceStatus accepted = pps_accept_submission();
    if (accepted.state != TS_VALID) { pps_store_failure(accepted); return; }
    ts_write_batch_receipt(accepted);
}
