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
// Output widths: tables6,8,11 have4 words, tables7,9,12 one word, the other
// tables below PEV_OUTPUT_TABLES eight; arena0 (catalog) holds tables
// 0,1,6,7,11,12 and arena1 (output) the rest. Readers are straight-line.
[ForceInline]
public uint pev_output_width(uint table)
{
    uint bit = 1u << (table & 31u);
    return select(table < PEV_OUTPUT_TABLES,
        select((bit & 0x940u) != 0u, 4u, select((bit & 0x1280u) != 0u, 1u, 8u)), 0u);
}
public bool pev_output_descriptor(uint table, out EvidenceOutputTable desc)
{
    desc = (EvidenceOutputTable)0;
    // The descriptor has a fixed ABI location. Validate its physical/logical
    // batch extent before reading it, independent of protocol admission.
    uint batch_words; uint batch_stride;
    program_evidence_batch.GetDimensions(batch_words, batch_stride);
    uint logical_batch = program_evidence_params.batch_word_count;
    if (!((table < PEV_OUTPUT_TABLES) & (logical_batch >= PEV_BATCH_FIXED_WORDS) &
        (logical_batch <= batch_words))) return false;
    uint start = PEV_OUTPUT_DIRECTORY_WORD + table * 5u;
    EvidenceOutputTable read = {
        program_evidence_batch[start], program_evidence_batch[start + 1u],
        program_evidence_batch[start + 2u], program_evidence_batch[start + 3u],
        program_evidence_batch[start + 4u] };
    desc = read;
    uint expected_arena = select(((0x18C3u >> table) & 1u) != 0u, 0u, 1u);
    uint actual_catalog; uint actual_output; uint stride;
    program_evidence_catalog.GetDimensions(actual_catalog, stride);
    program_evidence_output.GetDimensions(actual_output, stride);
    bool catalog = read.arena == 0u;
    uint physical = select(catalog, program_evidence_params.catalog_word_count,
        program_evidence_params.output_word_count);
    uint actual = select(catalog, actual_catalog, actual_output);
    return (read.arena == expected_arena) & (read.width == pev_output_width(table)) &
        (read.count <= read.capacity) & ((read.capacity != 0u) | (read.offset == 0u)) &
        (physical <= actual) & pev_word_span(read.offset, read.capacity, read.width, physical);
}
public bool pev_output_span_address(uint table, uint row, uint field, uint fields,
    out uint arena, out uint address)
{
    arena = PEV_INVALID; address = PEV_INVALID; EvidenceOutputTable desc;
    bool known = pev_output_descriptor(table, desc);
    if (!(known & (row < desc.count) & (fields != 0u) & (field < desc.width) &
        (fields <= desc.width - field))) return false;
    arena = desc.arena; address = desc.offset + row * desc.width + field; return true;
}
[ForceInline]
public bool pev_output_address(uint table, uint row, uint field, out uint arena, out uint address)
{ return pev_output_span_address(table, row, field, 1u, arena, address); }
public bool pev_output_read(uint table, uint row, uint field, out uint value)
{
    value = PEV_INVALID; uint arena; uint address;
    if (!pev_output_address(table, row, field, arena, address)) return false;
    if (arena == 0u) value = program_evidence_catalog[address];
    else value = program_evidence_output[address];
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
// Index and result records have one physical in-row span. Prove it once and
// retain scalar storage accesses: packed table starts need not be vector aligned.
public bool pev_output_read4(uint table, uint row, uint first_field, out uint4 value)
{
    value = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID);
    uint arena; uint address;
    if (!pev_output_span_address(table, row, first_field, 4u, arena, address)) return false;
    if (arena == 0u)
        value = uint4(program_evidence_catalog[address], program_evidence_catalog[address + 1u],
            program_evidence_catalog[address + 2u], program_evidence_catalog[address + 3u]);
    else
        value = uint4(program_evidence_output[address], program_evidence_output[address + 1u],
            program_evidence_output[address + 2u], program_evidence_output[address + 3u]);
    return true;
}
public bool pev_output_write8(uint table, uint row, uint4 low, uint4 high)
{
    uint arena; uint address;
    if (!pev_output_span_address(table, row, 0u, 8u, arena, address)) return false;
    // Complete ordinary records are observed after a dispatch barrier. Publish
    // the leading field last; concurrent receipt failures use their CAS owner.
    if (arena == 0u)
    {
        program_evidence_catalog[address + 1u] = low.y;
        program_evidence_catalog[address + 2u] = low.z;
        program_evidence_catalog[address + 3u] = low.w;
        program_evidence_catalog[address + 4u] = high.x;
        program_evidence_catalog[address + 5u] = high.y;
        program_evidence_catalog[address + 6u] = high.z;
        program_evidence_catalog[address + 7u] = high.w;
        program_evidence_catalog[address] = low.x;
    }
    else
    {
        program_evidence_output[address + 1u] = low.y;
        program_evidence_output[address + 2u] = low.z;
        program_evidence_output[address + 3u] = low.w;
        program_evidence_output[address + 4u] = high.x;
        program_evidence_output[address + 5u] = high.y;
        program_evidence_output[address + 6u] = high.z;
        program_evidence_output[address + 7u] = high.w;
        program_evidence_output[address] = low.x;
    }
    return true;
}
public bool pev_write_status(uint table, uint row, EvidenceStatus status)
{
    return pev_output_write8(table, row,
        uint4(status.state, status.detail, status.subject_row, status.related_row),
        uint4(status.required, status.available, 0u, 0u));
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
    // Both initializers call this before publishing BUILDING. Descriptor readers
    // only prove bounds and cannot supply the protocol/epoch admission gate.
    if (!pev_header_is_valid()) return pev_invalid(1u, PEV_INVALID, PEV_INVALID);
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
        else if (table == 1u || table == 11u) { if (!pev_catalog_count(9u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 2u) { if (!pev_table_count(13u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 3u || table == 5u) { if (!pev_table_count(16u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 4u) { if (!pev_table_count(15u, expected)) return pev_invalid(1u, table, PEV_INVALID); }
        else if (table == 6u) expected = work_rows;
        else if (table == 7u || table == 12u) expected = work_buckets;
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
    return pev_header_is_valid() && pev_output_read(0u, 0u, 0u, state) &&
        state == PEV_CATALOG_BUILDING;
}
// Failure record field 1..5: detail, subject, related, required, available;
// field 6 the given serial word; field 7 zero.
public uint pev_failure_field(EvidenceStatus status, uint field, uint serial)
{
    uint value = select(field == 6u, serial, 0u);
    value = select(field == 5u, status.available, value);
    value = select(field == 4u, status.required, value);
    value = select(field == 3u, status.related_row, value);
    value = select(field == 2u, status.subject_row, value);
    return select(field == 1u, status.detail, value);
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
    // Fields 1..7 in order through one write site.
    [loop]
    for (uint field = 1u; field < 8u; field++)
        pev_output_write(0u, 0u, field, pev_failure_field(status, field, 0u));
    // Only the thread that claimed BUILDING->BUSY may publish this failure.
    // Use CAS here too: Slang2026.2 mislowers InterlockedExchange.
    InterlockedCompareExchange(program_evidence_catalog[address], PEV_CATALOG_BUSY, status.state, previous);
}
public bool pev_dispatch_row(uint local, uint logical_count, out uint row)
{
    row = PEV_INVALID;
    if (local >= program_evidence_params.dispatch_count || program_evidence_params.dispatch_first > logical_count ||
        local >= logical_count - program_evidence_params.dispatch_first) return false;
    row = program_evidence_params.dispatch_first + local; return true;
}
