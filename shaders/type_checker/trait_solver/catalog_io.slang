import type_checker.trait_solver.abi;

public static const uint TS_CATALOG_BUSY = 0x80000000u;
public static const uint TS_CATALOG_BUILDING = 0x80000001u;
public static const uint TS_CHAIN_LIMIT = 1024u;
public struct SolverOutputTable
{
    public uint arena; public uint offset; public uint count; public uint capacity; public uint width;
}
public bool ts_catalog_count(uint table, out uint count)
{
    count = 0u; SolverTable desc;
    if (!ts_descriptor(table, desc)) return false;
    count = desc.catalog_count; return true;
}
public bool ts_bucket_count(uint rows, out uint buckets)
{
    buckets = 1u;
    if (rows > 0x40000000u) return false;
    uint required = max(1u, rows * 2u);
    for (uint bit = 0u; bit < 31u && buckets < required; bit++) buckets <<= 1u;
    return buckets >= required;
}
public bool ts_work_counts(out uint rows, out uint buckets)
{
    rows = 0u; buckets = 0u; uint atoms; uint implementations;
    if (!ts_catalog_count(1u, atoms) || !ts_catalog_count(9u, implementations)) return false;
    rows = max(atoms, implementations);
    return ts_bucket_count(rows, buckets);
}
// Output widths: tables6,8,11 have4 words, tables7,9,12 one word, the other
// tables below TS_OUTPUT_TABLES eight; arena0 (catalog) holds tables
// 0,1,6,7,11,12 and arena1 (output) the rest. Readers are straight-line.
[ForceInline]
public uint ts_output_width(uint table)
{
    uint bit = 1u << (table & 31u);
    return select(table < TS_OUTPUT_TABLES,
        select((bit & 0x940u) != 0u, 4u, select((bit & 0x1280u) != 0u, 1u, 8u)), 0u);
}
public bool ts_output_descriptor(uint table, out SolverOutputTable desc)
{
    desc = (SolverOutputTable)0;
    // The descriptor has a fixed ABI location. Validate its physical/logical
    // batch extent before reading it, independent of protocol admission.
    uint batch_words; uint batch_stride;
    trait_solver_batch.GetDimensions(batch_words, batch_stride);
    uint logical_batch = trait_solver_params.batch_word_count;
    if (!((table < TS_OUTPUT_TABLES) & (logical_batch >= TS_BATCH_FIXED_WORDS) &
        (logical_batch <= batch_words))) return false;
    uint start = TS_OUTPUT_DIRECTORY_WORD + table * 5u;
    SolverOutputTable read = {
        trait_solver_batch[start], trait_solver_batch[start + 1u],
        trait_solver_batch[start + 2u], trait_solver_batch[start + 3u],
        trait_solver_batch[start + 4u] };
    desc = read;
    uint expected_arena = select(((0x18C3u >> table) & 1u) != 0u, 0u, 1u);
    uint actual_catalog; uint actual_output; uint stride;
    trait_solver_catalog.GetDimensions(actual_catalog, stride);
    trait_solver_output.GetDimensions(actual_output, stride);
    bool catalog = read.arena == 0u;
    uint physical = select(catalog, trait_solver_params.catalog_word_count,
        trait_solver_params.output_word_count);
    uint actual = select(catalog, actual_catalog, actual_output);
    return (read.arena == expected_arena) & (read.width == ts_output_width(table)) &
        (read.count <= read.capacity) & ((read.capacity != 0u) | (read.offset == 0u)) &
        (physical <= actual) & ts_word_span(read.offset, read.capacity, read.width, physical);
}
public bool ts_output_span_address(uint table, uint row, uint field, uint fields,
    out uint arena, out uint address)
{
    arena = TS_INVALID; address = TS_INVALID; SolverOutputTable desc;
    bool known = ts_output_descriptor(table, desc);
    if (!(known & (row < desc.count) & (fields != 0u) & (field < desc.width) &
        (fields <= desc.width - field))) return false;
    arena = desc.arena; address = desc.offset + row * desc.width + field; return true;
}
[ForceInline]
public bool ts_output_address(uint table, uint row, uint field, out uint arena, out uint address)
{ return ts_output_span_address(table, row, field, 1u, arena, address); }
public bool ts_output_read(uint table, uint row, uint field, out uint value)
{
    value = TS_INVALID; uint arena; uint address;
    if (!ts_output_address(table, row, field, arena, address)) return false;
    if (arena == 0u) value = trait_solver_catalog[address];
    else value = trait_solver_output[address];
    return true;
}
public bool ts_output_write(uint table, uint row, uint field, uint value)
{
    uint arena; uint address;
    if (!ts_output_address(table, row, field, arena, address)) return false;
    if (arena == 0u) trait_solver_catalog[address] = value;
    else trait_solver_output[address] = value;
    return true;
}
// Index and result records have one physical in-row span. Prove it once and
// retain scalar storage accesses: packed table starts need not be vector aligned.
public bool ts_output_read4(uint table, uint row, uint first_field, out uint4 value)
{
    value = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID);
    uint arena; uint address;
    if (!ts_output_span_address(table, row, first_field, 4u, arena, address)) return false;
    if (arena == 0u)
        value = uint4(trait_solver_catalog[address], trait_solver_catalog[address + 1u],
            trait_solver_catalog[address + 2u], trait_solver_catalog[address + 3u]);
    else
        value = uint4(trait_solver_output[address], trait_solver_output[address + 1u],
            trait_solver_output[address + 2u], trait_solver_output[address + 3u]);
    return true;
}
public bool ts_output_write8(uint table, uint row, uint4 low, uint4 high)
{
    uint arena; uint address;
    if (!ts_output_span_address(table, row, 0u, 8u, arena, address)) return false;
    // Complete ordinary records are observed after a dispatch barrier. Publish
    // the leading field last; concurrent receipt failures use their CAS owner.
    if (arena == 0u)
    {
        trait_solver_catalog[address + 1u] = low.y;
        trait_solver_catalog[address + 2u] = low.z;
        trait_solver_catalog[address + 3u] = low.w;
        trait_solver_catalog[address + 4u] = high.x;
        trait_solver_catalog[address + 5u] = high.y;
        trait_solver_catalog[address + 6u] = high.z;
        trait_solver_catalog[address + 7u] = high.w;
        trait_solver_catalog[address] = low.x;
    }
    else
    {
        trait_solver_output[address + 1u] = low.y;
        trait_solver_output[address + 2u] = low.z;
        trait_solver_output[address + 3u] = low.w;
        trait_solver_output[address + 4u] = high.x;
        trait_solver_output[address + 5u] = high.y;
        trait_solver_output[address + 6u] = high.z;
        trait_solver_output[address + 7u] = high.w;
        trait_solver_output[address] = low.x;
    }
    return true;
}
public bool ts_write_status(uint table, uint row, SolverStatus status)
{
    return ts_output_write8(table, row,
        uint4(status.state, status.detail, status.subject_row, status.related_row),
        uint4(status.required, status.available, 0u, 0u));
}

// Submission-wide receipt, deliberately distinct from a generic Status8.
// A caller may publish VALID only after every batch admission/selection/replay
// phase has completed and its writes are visible. This helper is not that gate.
public bool ts_write_batch_receipt(SolverStatus status)
{
    if (!ts_header_is_valid()) return false;
    return ts_output_write(10u, 0u, 1u, status.detail) &&
        ts_output_write(10u, 0u, 2u, status.subject_row) &&
        ts_output_write(10u, 0u, 3u, status.related_row) &&
        ts_output_write(10u, 0u, 4u, status.required) &&
        ts_output_write(10u, 0u, 5u, status.available) &&
        ts_output_write(10u, 0u, 6u, trait_solver_batch[4u]) &&
        ts_output_write(10u, 0u, 7u, 0u) &&
        ts_output_write(10u, 0u, 0u, status.state);
}

// Called once before any other catalog writer. Malformed output layout leaves
// the host-initialized receipt UNPROCESSED, which is never an accepted catalog.
public SolverStatus ts_admit_output_layout()
{
    // Both initializers call this before publishing BUILDING. Descriptor readers
    // only prove bounds and cannot supply the protocol/epoch admission gate.
    if (!ts_header_is_valid()) return ts_invalid(1u, TS_INVALID, TS_INVALID);
    uint output_words; uint stride;
    trait_solver_output.GetDimensions(output_words, stride);
    if (trait_solver_params.output_word_count > output_words)
        return ts_limit(20u, 2u, trait_solver_params.output_word_count, output_words);
    uint work_rows; uint work_buckets;
    if (!ts_work_counts(work_rows, work_buckets)) return ts_invalid(19u, 6u, TS_INVALID);
    for (uint table = 0u; table < TS_OUTPUT_TABLES; table++)
    {
        SolverOutputTable current;
        if (!ts_output_descriptor(table, current)) return ts_invalid(1u, table, TS_INVALID);
        uint expected = 0u;
        if (table == 0u || table == 10u) expected = 1u;
        else if (table == 1u || table == 11u) { if (!ts_catalog_count(9u, expected)) return ts_invalid(1u, table, TS_INVALID); }
        else if (table == 2u) { if (!ts_table_count(13u, expected)) return ts_invalid(1u, table, TS_INVALID); }
        else if (table == 3u || table == 5u) { if (!ts_table_count(16u, expected)) return ts_invalid(1u, table, TS_INVALID); }
        else if (table == 4u) { if (!ts_table_count(15u, expected)) return ts_invalid(1u, table, TS_INVALID); }
        else if (table == 6u) expected = work_rows;
        else if (table == 7u || table == 12u) expected = work_buckets;
        else if (table == 8u) { if (!ts_table_count(14u, expected)) return ts_invalid(1u, table, TS_INVALID); }
        else if (table == 9u)
        {
            uint assumptions;
            if (!ts_table_count(14u, assumptions) || !ts_bucket_count(assumptions, expected))
                return ts_invalid(19u, table, TS_INVALID);
        }
        if (current.count != expected) return ts_invalid(19u, table, current.count);
        uint end = current.offset + current.capacity * current.width;
        if (current.arena == 0u && current.capacity != 0u)
        {
            if (current.offset < 4u) return ts_invalid(1u, table, TS_INVALID);
            for (uint source = 0u; source < TS_TABLES; source++)
            {
                SolverTable input;
                if (!ts_descriptor(source, input)) return ts_invalid(1u, source, TS_INVALID);
                if (input.catalog_count != 0u && current.offset < input.catalog_offset + input.catalog_count * input.width &&
                    input.catalog_offset < end) return ts_invalid(1u, table, source);
            }
        }
        for (uint prior = 0u; prior < table; prior++)
        {
            SolverOutputTable other;
            if (!ts_output_descriptor(prior, other)) return ts_invalid(1u, prior, TS_INVALID);
            if (current.arena == other.arena && current.capacity != 0u && other.capacity != 0u &&
                current.offset < other.offset + other.capacity * other.width && other.offset < end)
                return ts_invalid(1u, table, prior);
        }
    }
    return ts_ok();
}

public bool ts_catalog_is_building()
{
    uint state;
    return ts_header_is_valid() && ts_output_read(0u, 0u, 0u, state) &&
        state == TS_CATALOG_BUILDING;
}
// Failure record field 1..5: detail, subject, related, required, available;
// field 6 the given serial word; field 7 zero.
public uint ts_failure_field(SolverStatus status, uint field, uint serial)
{
    uint value = select(field == 6u, serial, 0u);
    value = select(field == 5u, status.available, value);
    value = select(field == 4u, status.required, value);
    value = select(field == 3u, status.related_row, value);
    value = select(field == 2u, status.subject_row, value);
    return select(field == 1u, status.detail, value);
}
public void ts_catalog_failure(SolverStatus status)
{
    if (status.state == TS_VALID) return;
    uint arena; uint address;
    if (!ts_output_address(0u, 0u, 0u, arena, address) || arena != 0u) return;
    uint previous;
    InterlockedCompareExchange(trait_solver_catalog[address], TS_CATALOG_BUILDING, TS_CATALOG_BUSY, previous);
    if (previous != TS_CATALOG_BUILDING) return;
    // One winner owns every diagnostic field; no mixed failure record races.
    // Fields 1..7 in order through one write site.
    [loop]
    for (uint field = 1u; field < 8u; field++)
        ts_output_write(0u, 0u, field, ts_failure_field(status, field, 0u));
    // Only the thread that claimed BUILDING->BUSY may publish this failure.
    // Use CAS here too: Slang2026.2 mislowers InterlockedExchange.
    InterlockedCompareExchange(trait_solver_catalog[address], TS_CATALOG_BUSY, status.state, previous);
}
public bool ts_dispatch_row(uint local, uint logical_count, out uint row)
{
    row = TS_INVALID;
    if (local >= trait_solver_params.dispatch_count || trait_solver_params.dispatch_first > logical_count ||
        local >= logical_count - trait_solver_params.dispatch_first) return false;
    row = trait_solver_params.dispatch_first + local; return true;
}
