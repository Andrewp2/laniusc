import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;

public static const uint PEV_BATCH_BUILDING = 0x80000001u;
public static const uint PEV_BATCH_BUSY = 0x80000000u;

public bool pev_catalog_is_valid()
{
    uint state;
    // Every batch work/finish gate reaches this before reading the serial.
    return pev_header_is_valid() && pev_output_read(0u, 0u, 0u, state) && state == PEV_VALID;
}
public bool pev_batch_is_building()
{
    uint state; uint serial;
    return pev_catalog_is_valid() && pev_output_read(10u, 0u, 0u, state) &&
        state == PEV_BATCH_BUILDING && pev_output_read(10u, 0u, 6u, serial) &&
        serial == program_evidence_batch[4u];
}
public void pev_batch_failure(EvidenceStatus status)
{
    if (status.state == PEV_VALID) return;
    uint arena; uint address;
    if (!pev_output_address(10u, 0u, 0u, arena, address) || arena != 1u) return;
    uint previous;
    InterlockedCompareExchange(program_evidence_output[address], PEV_BATCH_BUILDING, PEV_BATCH_BUSY, previous);
    if (previous != PEV_BATCH_BUILDING) return;
    pev_output_write(10u, 0u, 1u, status.detail);
    pev_output_write(10u, 0u, 2u, status.subject_row);
    pev_output_write(10u, 0u, 3u, status.related_row);
    pev_output_write(10u, 0u, 4u, status.required);
    pev_output_write(10u, 0u, 5u, status.available);
    pev_output_write(10u, 0u, 6u, program_evidence_batch[4u]);
    pev_output_write(10u, 0u, 7u, 0u);
    // Only the BUILDING->BUSY winner owns this failure record. Use CAS for
    // atomic publication: Slang2026.2 mislowers InterlockedExchange.
    InterlockedCompareExchange(program_evidence_output[address], PEV_BATCH_BUSY, status.state, previous);
}
public void pev_batch_initialize()
{
    // Layout rejection must leave trusted host-initialized state UNPROCESSED;
    // it must never enable later writers. The receipt is reset EVERY submission.
    EvidenceStatus status = pev_admit_output_layout();
    if (status.state != PEV_VALID) return;
    EvidenceStatus building = pev_ok(); building.state = PEV_BATCH_BUILDING;
    pev_write_batch_receipt(building);
    status = pev_admit_directories();
    if (status.state != PEV_VALID) { pev_batch_failure(status); return; }
    if (!pev_catalog_is_valid()) pev_batch_failure(pev_invalid(15u, 0u, PEV_INVALID));
}
public bool pev_context_goal_scope(uint context, out uint owner, out bool closed)
{
    owner = PEV_INVALID; closed = false; uint4 low; uint4 high;
    if (!pev_read4(13u, context, 0u, low) || !pev_read4(13u, context, 4u, high) || high.y > 2u) return false;
    owner = low.y; closed = high.y == 1u; return true;
}
public bool pev_output_evidence(uint obligation, uint4 low, uint4 high)
{
    return pev_output_write8(5u, obligation, low, high);
}
public void pev_obligation_status(uint obligation, uint state, uint detail, uint evidence,
    uint candidate, uint conflicting, uint required, uint available)
{
    pev_output_write8(3u, obligation, uint4(state, detail, evidence, candidate),
        uint4(conflicting, required, available, 0u));
}
public void pev_obligation_failure(uint obligation, EvidenceStatus status)
{
    uint state = status.state == PEV_RESOURCE_LIMIT ? 5u :
        (status.state == PEV_UNSUPPORTED ? 6u : (status.state == PEV_COHERENCE_CONFLICT ? 7u : 4u));
    pev_obligation_status(obligation, state, status.detail, PEV_INVALID,
        PEV_INVALID, status.related_row, status.required, status.available);
}
