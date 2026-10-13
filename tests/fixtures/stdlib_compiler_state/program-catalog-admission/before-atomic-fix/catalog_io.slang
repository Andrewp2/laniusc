import type_checker.program_evidence.abi;

public static const uint PEV_CATALOG_BUSY = 0x80000000u;
public static const uint PEV_CATALOG_BUILDING = 0x80000001u;
public static const uint PEV_CHAIN_LIMIT = 1024u;
public struct EvidenceOutputTable
{
    public uint arena; public uint offset; public uint count; public uint capacity; public uint width;
}
public bool pev_catalog_count(uint table, out uint count)
{
    count = 0u; EvidenceTable desc;
    if (!pev_descriptor(table, desc)) return false;
    count = desc.catalog_count; return true;
}
public bool pev_bucket_count(uint rows, out uint buckets)
{
    buckets = 1u;
    if (rows > 0x40000000u) return false;
    uint required = max(1u, rows * 2u);
    for (uint bit = 0u; bit < 31u && buckets < required; bit++) buckets <<= 1u;
    return buckets >= required;
}
public bool pev_work_counts(out uint rows, out uint buckets)
{
    rows = 0u; buckets = 0u; uint atoms; uint implementations;
    if (!pev_catalog_count(1u, atoms) || !pev_catalog_count(9u, implementations)) return false;
    rows = max(atoms, implementations);
    return pev_bucket_count(rows, buckets);
}
public uint pev_output_width(uint table)
{
    if (table >= PEV_OUTPUT_TABLES) return 0u;
    if (table == 6u || table == 8u) return 4u;
    if (table == 7u || table == 9u) return 1u;
    return 8u;
}
public bool pev_output_descriptor(uint table, out EvidenceOutputTable desc)
{
    desc = (EvidenceOutputTable)0;
    if (table >= PEV_OUTPUT_TABLES || !pev_header_is_valid()) return false;
    uint start = program_evidence_batch[7u] + table * 5u;
    desc.arena = program_evidence_batch[start];
    desc.offset = program_evidence_batch[start + 1u];
    desc.count = program_evidence_batch[start + 2u];
    desc.capacity = program_evidence_batch[start + 3u];
    desc.width = program_evidence_batch[start + 4u];
    uint expected_arena = (table == 0u || table == 1u || table == 6u || table == 7u) ? 0u : 1u;
    if (desc.arena != expected_arena || desc.width != pev_output_width(table) ||
        desc.count > desc.capacity || (desc.capacity == 0u && desc.offset != 0u)) return false;
    uint physical = desc.arena == 0u ? program_evidence_params.catalog_word_count :
        program_evidence_params.output_word_count;
    uint actual; uint stride;
    if (desc.arena == 0u) program_evidence_catalog.GetDimensions(actual, stride);
    else program_evidence_output.GetDimensions(actual, stride);
    if (physical > actual) return false;
    return pev_word_span(desc.offset, desc.capacity, desc.width, physical);
}
public bool pev_output_address(uint table, uint row, uint field, out uint arena, out uint address)
{
    arena = PEV_INVALID; address = PEV_INVALID; EvidenceOutputTable desc;
    if (!pev_output_descriptor(table, desc) || row >= desc.count || field >= desc.width) return false;
    arena = desc.arena; address = desc.offset + row * desc.width + field; return true;
}
public bool pev_output_read(uint table, uint row, uint field, out uint value)
{
    value = PEV_INVALID; uint arena; uint address;
    if (!pev_output_address(table, row, field, arena, address)) return false;
    value = arena == 0u ? program_evidence_catalog[address] : program_evidence_output[address];
    return true;
}
public bool pev_output_write(uint table, uint row, uint field, uint value)
{
    uint arena; uint address;
    if (!pev_output_address(table, row, field, arena, address)) return false;
    if (arena == 0u) program_evidence_catalog[address] = value;
    else program_evidence_output[address] = value;
    return true;
}
public bool pev_write_status(uint table, uint row, EvidenceStatus status)
{
    return pev_output_write(table, row, 0u, status.state) &&
        pev_output_write(table, row, 1u, status.detail) &&
        pev_output_write(table, row, 2u, status.subject_row) &&
        pev_output_write(table, row, 3u, status.related_row) &&
        pev_output_write(table, row, 4u, status.required) &&
        pev_output_write(table, row, 5u, status.available) &&
        pev_output_write(table, row, 6u, 0u) && pev_output_write(table, row, 7u, 0u);
}

// Submission-wide receipt, deliberately distinct from a generic Status8.
// A caller may publish VALID only after every batch admission/selection/replay
// phase has completed and its writes are visible. This helper is not that gate.
public bool pev_write_batch_receipt(EvidenceStatus status)
{
    if (!pev_header_is_valid()) return false;
    return pev_output_write(10u, 0u, 1u, status.detail) &&
        pev_output_write(10u, 0u, 2u, status.subject_row) &&
        pev_output_write(10u, 0u, 3u, status.related_row) &&
        pev_output_write(10u, 0u, 4u, status.required) &&
        pev_output_write(10u, 0u, 5u, status.available) &&
        pev_output_write(10u, 0u, 6u, program_evidence_batch[4u]) &&
        pev_output_write(10u, 0u, 7u, 0u) &&
        pev_output_write(10u, 0u, 0u, status.state);
}

// Called once before any other catalog writer. Malformed output layout leaves
// the host-initialized receipt UNPROCESSED, which is never an accepted catalog.
public EvidenceStatus pev_admit_output_layout()
{
    uint output_words; uint stride;
    program_evidence_output.GetDimensions(output_words, stride);
    if (program_evidence_params.output_word_count > output_words)
        return pev_limit(20u, 2u, program_evidence_params.output_word_count, output_words);
    uint work_rows; uint work_buckets;
    if (!pev_work_counts(work_rows, work_buckets)) return pev_invalid(19u, 6u, PEV_INVALID);
    for (uint table = 0u; table < PEV_OUTPUT_TABLES; table++)
    {
        EvidenceOutputTable current;
        if (!pev_output_descriptor(table, current)) return pev_invalid(1u, table, PEV_INVALID);
        uint expected = 0u;
        if (table == 0u || table == 10u) expected = 1u;
        else if (table == 1u) { if (!pev_catalog_count(9u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 2u) { if (!pev_table_count(13u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 3u || table == 5u) { if (!pev_table_count(16u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 4u) { if (!pev_table_count(15u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 6u) expected = work_rows;
        else if (table == 7u) expected = work_buckets;
        else if (table == 8u) { if (!pev_table_count(14u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 9u)
        {
            uint assumptions;
            if (!pev_table_count(14u, assumptions) || !pev_bucket_count(assumptions, expected))
                return pev_invalid(19u, table, PEV_INVALID);
        }
        if (current.count != expected) return pev_invalid(19u, table, current.count);
        uint end = current.offset + current.capacity * current.width;
        if (current.arena == 0u && current.capacity != 0u)
        {
            if (current.offset < 4u) return pev_invalid(1u, table, PEV_INVALID);
            for (uint source = 0u; source < PEV_TABLES; source++)
            {
                EvidenceTable input;
                if (!pev_descriptor(source, input)) return pev_invalid(1u, source, PEV_INVALID);
                if (input.catalog_count != 0u && current.offset < input.catalog_offset + input.catalog_count * input.width &&
                    input.catalog_offset < end) return pev_invalid(1u, table, source);
            }
        }
        for (uint prior = 0u; prior < table; prior++)
        {
            EvidenceOutputTable other;
            if (!pev_output_descriptor(prior, other)) return pev_invalid(1u, prior, PEV_INVALID);
            if (current.arena == other.arena && current.capacity != 0u && other.capacity != 0u &&
                current.offset < other.offset + other.capacity * other.width && other.offset < end)
                return pev_invalid(1u, table, prior);
        }
    }
    return pev_ok();
}

public bool pev_catalog_is_building()
{
    uint state;
    return pev_output_read(0u, 0u, 0u, state) && state == PEV_CATALOG_BUILDING;
}
public void pev_catalog_failure(EvidenceStatus status)
{
    if (status.state == PEV_VALID) return;
    uint arena; uint address;
    if (!pev_output_address(0u, 0u, 0u, arena, address) || arena != 0u) return;
    uint previous;
    InterlockedCompareExchange(program_evidence_catalog[address], PEV_CATALOG_BUILDING, PEV_CATALOG_BUSY, previous);
    if (previous != PEV_CATALOG_BUILDING) return;
    // One winner owns every diagnostic field; no mixed failure record races.
    pev_output_write(0u, 0u, 1u, status.detail);
    pev_output_write(0u, 0u, 2u, status.subject_row);
    pev_output_write(0u, 0u, 3u, status.related_row);
    pev_output_write(0u, 0u, 4u, status.required);
    pev_output_write(0u, 0u, 5u, status.available);
    pev_output_write(0u, 0u, 6u, 0u); pev_output_write(0u, 0u, 7u, 0u);
    InterlockedExchange(program_evidence_catalog[address], status.state, previous);
}
public bool pev_dispatch_row(uint local, uint logical_count, out uint row)
{
    row = PEV_INVALID;
    if (local >= program_evidence_params.dispatch_count || program_evidence_params.dispatch_first > logical_count ||
        local >= logical_count - program_evidence_params.dispatch_first) return false;
    row = program_evidence_params.dispatch_first + local; return true;
}
