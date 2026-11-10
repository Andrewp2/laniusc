import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;

public static const uint TS_BATCH_BUILDING = 0x80000001u;
public static const uint TS_BATCH_BUSY = 0x80000000u;

public bool ts_catalog_is_valid()
{
    uint state;
    // Every batch work/finish gate reaches this before reading the serial.
    return ts_header_is_valid() && ts_output_read(0u, 0u, 0u, state) && state == TS_VALID;
}
public bool ts_batch_is_building()
{
    uint state; uint serial;
    return ts_catalog_is_valid() && ts_output_read(10u, 0u, 0u, state) &&
        state == TS_BATCH_BUILDING && ts_output_read(10u, 0u, 6u, serial) &&
        serial == trait_solver_batch[4u];
}
public void ts_batch_failure(EvidenceStatus status)
{
    if (status.state == TS_VALID) return;
    uint arena; uint address;
    if (!ts_output_address(10u, 0u, 0u, arena, address) || arena != 1u) return;
    uint previous;
    InterlockedCompareExchange(trait_solver_output[address], TS_BATCH_BUILDING, TS_BATCH_BUSY, previous);
    if (previous != TS_BATCH_BUILDING) return;
    // Fields 1..7 in order through one write site.
    uint serial = trait_solver_batch[4u];
    [loop]
    for (uint field = 1u; field < 8u; field++)
        ts_output_write(10u, 0u, field, ts_failure_field(status, field, serial));
    // Only the BUILDING->BUSY winner owns this failure record. Use CAS for
    // atomic publication: Slang2026.2 mislowers InterlockedExchange.
    InterlockedCompareExchange(trait_solver_output[address], TS_BATCH_BUSY, status.state, previous);
}
public void ts_batch_initialize()
{
    // Layout rejection must leave trusted host-initialized state UNPROCESSED;
    // it must never enable later writers. The receipt is reset EVERY submission.
    EvidenceStatus status = ts_admit_output_layout();
    if (status.state != TS_VALID) return;
    EvidenceStatus building = ts_ok(); building.state = TS_BATCH_BUILDING;
    ts_write_batch_receipt(building);
    status = ts_admit_directories();
    if (status.state != TS_VALID) { ts_batch_failure(status); return; }
    if (!ts_catalog_is_valid()) ts_batch_failure(ts_invalid(15u, 0u, TS_INVALID));
}
public bool ts_context_goal_scope(uint context, out uint owner, out bool closed)
{
    owner = TS_INVALID; closed = false; uint4 low; uint4 high;
    if (!ts_read4(13u, context, 0u, low) || !ts_read4(13u, context, 4u, high) || high.y > 2u) return false;
    owner = low.y; closed = high.y == 1u; return true;
}
public bool ts_output_evidence(uint obligation, uint4 low, uint4 high)
{
    return ts_output_write8(5u, obligation, low, high);
}
public void ts_obligation_status(uint obligation, uint state, uint detail, uint evidence,
    uint candidate, uint conflicting, uint required, uint available)
{
    ts_output_write8(3u, obligation, uint4(state, detail, evidence, candidate),
        uint4(conflicting, required, available, 0u));
}
// A proven root. Word 7 is the catalog implementation that an
// implementation proof applies plus one, 0 for an assumption proof: replay
// routes the instance's bound members to that implementation's methods.
public void ts_obligation_proven(uint obligation, uint state, uint proof, uint kind, uint source)
{
    ts_output_write8(3u, obligation, uint4(state, 0u, obligation, proof),
        uint4(TS_INVALID, 0u, 0u, kind == 1u ? source + 1u : 0u));
}
public void ts_obligation_failure(uint obligation, EvidenceStatus status)
{
    uint state = status.state == TS_RESOURCE_LIMIT ? 5u :
        (status.state == TS_UNSUPPORTED ? 6u : (status.state == TS_COHERENCE_CONFLICT ? 7u : 4u));
    ts_obligation_status(obligation, state, status.detail, TS_INVALID,
        TS_INVALID, status.related_row, status.required, status.available);
}
