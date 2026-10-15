import primitive_types;
// Every address is checked before dereference. Logical row IDs span a frozen
// catalog prefix followed by a retained batch suffix; capacity is not identity.
public static const uint PEV_INVALID = 0xffffffffu;
public static const uint PEV_MAGIC = 0x50455631u;
public static const uint PEV_VERSION = 3u;
public static const uint PEV_TABLES = 18u;
public static const uint PEV_OUTPUT_TABLES = 13u;
public static const uint PEV_DIRECTORY_WORD = 8u;
public static const uint PEV_OUTPUT_DIRECTORY_WORD = PEV_DIRECTORY_WORD + PEV_TABLES * 6u;
public static const uint PEV_BATCH_FIXED_WORDS = PEV_OUTPUT_DIRECTORY_WORD + PEV_OUTPUT_TABLES * 5u;
public static const uint PEV_VALID = 1u;
public static const uint PEV_INVALID_INPUT = 2u;
public static const uint PEV_RESOURCE_LIMIT = 3u;
public static const uint PEV_UNSUPPORTED = 4u;
public static const uint PEV_COHERENCE_CONFLICT = 5u;
public static const uint PEV_OBLIGATION_FAILURE = 6u;
public static const uint PEV_DEPTH_LIMIT = 64u;
public static const uint PEV_VISIT_LIMIT = 65536u;

public struct EvidenceStatus
{
    public uint state; public uint detail; public uint subject_row; public uint related_row;
    public uint required; public uint available;
}
// One non-inlined constructor: the status helpers below are inlined at
// thousands of return sites, each becoming a single call.
public EvidenceStatus pev_status(uint state, uint detail, uint subject, uint related,
    uint required, uint available)
{
    EvidenceStatus r;
    r.state = state; r.detail = detail; r.subject_row = subject; r.related_row = related;
    r.required = required; r.available = available;
    return r;
}
[ForceInline]
public EvidenceStatus pev_ok()
{ return pev_status(PEV_VALID, 0u, PEV_INVALID, PEV_INVALID, 0u, 0u); }
[ForceInline]
public EvidenceStatus pev_invalid(uint detail, uint subject, uint related)
{ return pev_status(PEV_INVALID_INPUT, detail, subject, related, 0u, 0u); }
[ForceInline]
public EvidenceStatus pev_limit(uint detail, uint subject, uint required, uint available)
{ return pev_status(PEV_RESOURCE_LIMIT, detail, subject, PEV_INVALID, required, available); }
public struct ProgramEvidenceParams
{
    public uint dispatch_first; public uint dispatch_count; public uint catalog_word_count; public uint batch_word_count;
    public uint output_word_count; public uint phase;
    // Logical extents of the native-layout sidecars (0 when not bound). Those
    // arenas bind their whole retained allocation; see plr/plm_logical_words.
    public uint recipe_word_count; public uint work_word_count;
}
public ConstantBuffer<ProgramEvidenceParams> program_evidence_params;
// One resource binding avoids overlapping RO/RW aliases during catalog build.
// After the freeze phase the dispatcher binds this arena read-only in policy;
// later entry points never call a catalog writer.
public RWStructuredBuffer<uint> program_evidence_catalog;
public StructuredBuffer<uint> program_evidence_batch;
public RWStructuredBuffer<uint> program_evidence_output;

public struct EvidenceTable
{
    public uint catalog_offset; public uint catalog_count; public uint batch_offset;
    public uint batch_count; public uint batch_capacity; public uint width;
}

// Fixed row widths, one nibble per table (low nibble first): tables0-7
// 4,8,9,4,4,8,2,2; tables8-15 8,12,6,5,4,8,6,8; tables16-17 4,8; else 0.
// Readers are inlined hundreds of times per kernel, so every reader below is
// a straight-line select/mask computation with one guarded early return.
[ForceInline]
public uint pev_expected_width(uint table)
{
    uint packed = select(table < 8u, 0x22844984u, select(table < 16u, 0x868456C8u, 0x00000084u));
    return select(table < PEV_TABLES, (packed >> ((table & 7u) * 4u)) & 15u, 0u);
}
// Division by a selected nonzero width never changes a result whose width
// term is false; it only keeps the expression free of a branch.
[ForceInline]
public uint pev_rows_in(uint offset, uint words, uint width)
{ return (words - offset) / select(width == 0u, 1u, width); }
[ForceInline]
public bool pev_word_span(uint offset, uint rows, uint width, uint words)
{
    return (width != 0u) & (offset <= words) & (rows <= pev_rows_in(offset, words, width));
}

// This small fixed header check is safe even when the logical lengths are bad.
public bool pev_header_is_valid()
{
    uint catalog_words; uint catalog_stride; uint batch_words; uint batch_stride;
    program_evidence_catalog.GetDimensions(catalog_words, catalog_stride);
    program_evidence_batch.GetDimensions(batch_words, batch_stride);
    uint c = program_evidence_params.catalog_word_count;
    uint b = program_evidence_params.batch_word_count;
    if (c < 4u || b < PEV_BATCH_FIXED_WORDS || c > catalog_words || b > batch_words)
        return false;
    if (program_evidence_catalog[0u] != PEV_MAGIC ||
        program_evidence_catalog[1u] != PEV_VERSION ||
        program_evidence_batch[0u] != PEV_MAGIC ||
        program_evidence_batch[1u] != PEV_VERSION ||
        program_evidence_catalog[2u] != program_evidence_batch[2u] ||
        program_evidence_catalog[3u] != program_evidence_batch[3u] ||
        program_evidence_batch[5u] != PEV_TABLES ||
        program_evidence_batch[6u] != PEV_DIRECTORY_WORD ||
        program_evidence_batch[7u] != PEV_OUTPUT_DIRECTORY_WORD)
        return false;
    return true;
}

public bool pev_descriptor(uint table, out EvidenceTable desc)
{
    desc = (EvidenceTable)0;
    // Protocol identity is checked by initialization/work/publication gates.
    // This reader independently proves physical safety; no cached admission or
    // capacity value substitutes for logical row membership.
    uint actual_catalog; uint actual_batch; uint stride;
    program_evidence_catalog.GetDimensions(actual_catalog, stride);
    program_evidence_batch.GetDimensions(actual_batch, stride);
    uint catalog_words = program_evidence_params.catalog_word_count;
    uint batch_words = program_evidence_params.batch_word_count;
    if (!((table < PEV_TABLES) & (catalog_words >= 4u) & (batch_words >= PEV_BATCH_FIXED_WORDS) &
        (catalog_words <= actual_catalog) & (batch_words <= actual_batch))) return false;
    // table < PEV_TABLES and the fixed header bound prove all six words.
    uint start = PEV_DIRECTORY_WORD + table * 6u;
    EvidenceTable read = {
        program_evidence_batch[start], program_evidence_batch[start + 1u],
        program_evidence_batch[start + 2u], program_evidence_batch[start + 3u],
        program_evidence_batch[start + 4u], program_evidence_batch[start + 5u] };
    desc = read;
    // Tables 0,2,3,4,8,9,10 are catalog-only; tables from 11 are batch-only.
    bool catalog_only = ((0x71Du >> (table & 31u)) & 1u) != 0u;
    bool batch_only = table >= 11u;
    return (read.width == pev_expected_width(table)) &
        (read.batch_count <= read.batch_capacity) & (read.batch_count != PEV_INVALID) &
        (read.catalog_count <= PEV_INVALID - 1u - read.batch_count) &
        ((read.catalog_count != 0u) | (read.catalog_offset == 0u)) &
        ((read.batch_capacity != 0u) | (read.batch_offset == 0u)) &
        pev_word_span(read.catalog_offset, read.catalog_count, read.width, catalog_words) &
        pev_word_span(read.batch_offset, read.batch_capacity, read.width, batch_words) &
        (!catalog_only | (read.batch_capacity == 0u)) & (!batch_only | (read.catalog_count == 0u));
}

// This is a safe directory projection, not descriptor admission. Initialization
// validates every table's width, arena domain, capacity, complete extents and
// disjointness before any work phase. The input directory then stays immutable.
// Counts alone are also used to derive output sizes during initialization; that
// initializer still requires full descriptor admission before any table writer.
public bool pev_input_table_rows(uint table, out uint directory,
    out uint catalog_count, out uint batch_count)
{
    directory = PEV_INVALID; catalog_count = 0u; batch_count = 0u;
    uint actual_batch; uint stride;
    program_evidence_batch.GetDimensions(actual_batch, stride);
    uint batch_words = program_evidence_params.batch_word_count;
    if (!((table < PEV_TABLES) & (batch_words >= PEV_BATCH_FIXED_WORDS) &
        (batch_words <= actual_batch))) return false;
    uint start = PEV_DIRECTORY_WORD + table * 6u;
    uint prefix = program_evidence_batch[start + 1u];
    uint suffix = program_evidence_batch[start + 3u];
    if (!((suffix != PEV_INVALID) & (prefix <= PEV_INVALID - 1u - suffix))) return false;
    directory = start; catalog_count = prefix; batch_count = suffix;
    return true;
}
public bool pev_table_count(uint table, out uint count)
{
    count = 0u;
    uint directory; uint catalog_count; uint batch_count;
    if (!pev_input_table_rows(table, directory, catalog_count, batch_count)) return false;
    count = catalog_count + batch_count;
    return true;
}
public bool pev_row_span(uint table, uint first, uint count)
{
    uint total;
    bool known = pev_table_count(table, total);
    return known & (first <= total) & (count <= total - first);
}
// Independent address safety does not require re-admitting unrelated rows or
// the other arena's full table capacity. The fixed ABI width and exact logical
// prefix/suffix select one row, whose entire extent must fit in the logical and
// actual selected buffer before any address multiplication or addition.
// The directory guard is the only branch: it makes the fixed directory reads
// safe; every remaining condition is pure and combined without short-circuit.
public bool pev_read_address(uint table, uint row, uint first_field, uint fields,
    out uint arena, out uint address)
{
    arena = PEV_INVALID; address = PEV_INVALID;
    uint actual_catalog; uint actual_batch; uint stride;
    program_evidence_catalog.GetDimensions(actual_catalog, stride);
    program_evidence_batch.GetDimensions(actual_batch, stride);
    uint batch_words = program_evidence_params.batch_word_count;
    if (!((table < PEV_TABLES) & (batch_words >= PEV_BATCH_FIXED_WORDS) &
        (batch_words <= actual_batch))) return false;
    uint start = PEV_DIRECTORY_WORD + table * 6u;
    uint catalog_count = program_evidence_batch[start + 1u];
    uint batch_count = program_evidence_batch[start + 3u];
    uint width = pev_expected_width(table);
    bool in_catalog = row < catalog_count;
    uint local = select(in_catalog, row, row - catalog_count);
    uint offset = program_evidence_batch[start + select(in_catalog, 0u, 2u)];
    uint words = select(in_catalog, program_evidence_params.catalog_word_count, batch_words);
    uint actual = select(in_catalog, actual_catalog, actual_batch);
    // width is nonzero for every admitted table ID. Division avoids overflow
    // even for arbitrary malformed offsets/counts, without trusting capacity.
    if (!((batch_count != PEV_INVALID) & (catalog_count <= PEV_INVALID - 1u - batch_count) &
        (fields != 0u) & (first_field < width) & (fields <= width - first_field) &
        (in_catalog | (local < batch_count)) & (words <= actual) & (offset <= words) &
        (local < pev_rows_in(offset, words, width)))) return false;
    arena = select(in_catalog, 0u, 1u); address = offset + local * width + first_field;
    return true;
}
public bool pev_word(uint table, uint row, uint field, out uint value)
{
    value = PEV_INVALID; uint arena; uint address;
    if (!pev_read_address(table, row, field, 1u, arena, address)) return false;
    if (arena == 0u) value = program_evidence_catalog[address];
    else value = program_evidence_batch[address];
    return true;
}
public bool pev_read2(uint table, uint row, uint first_field, out uint2 value)
{
    value = uint2(PEV_INVALID, PEV_INVALID); uint arena; uint address;
    if (!pev_read_address(table, row, first_field, 2u, arena, address)) return false;
    // Preserve scalar storage addressing: packed rows need not be vector aligned.
    if (arena == 0u)
        value = uint2(program_evidence_catalog[address], program_evidence_catalog[address + 1u]);
    else
        value = uint2(program_evidence_batch[address], program_evidence_batch[address + 1u]);
    return true;
}
public bool pev_read4(uint table, uint row, uint first_field, out uint4 value)
{
    value = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); uint arena; uint address;
    if (!pev_read_address(table, row, first_field, 4u, arena, address)) return false;
    if (arena == 0u)
        value = uint4(program_evidence_catalog[address], program_evidence_catalog[address + 1u],
            program_evidence_catalog[address + 2u], program_evidence_catalog[address + 3u]);
    else
        value = uint4(program_evidence_batch[address], program_evidence_batch[address + 1u],
            program_evidence_batch[address + 2u], program_evidence_batch[address + 3u]);
    return true;
}
public bool pev_read8(uint table, uint row, out uint4 low, out uint4 high)
{
    low = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); high = low;
    uint arena; uint address;
    if (!pev_read_address(table, row, 0u, 8u, arena, address)) return false;
    if (arena == 0u)
    {
        low = uint4(program_evidence_catalog[address], program_evidence_catalog[address + 1u],
            program_evidence_catalog[address + 2u], program_evidence_catalog[address + 3u]);
        high = uint4(program_evidence_catalog[address + 4u], program_evidence_catalog[address + 5u],
            program_evidence_catalog[address + 6u], program_evidence_catalog[address + 7u]);
    }
    else
    {
        low = uint4(program_evidence_batch[address], program_evidence_batch[address + 1u],
            program_evidence_batch[address + 2u], program_evidence_batch[address + 3u]);
        high = uint4(program_evidence_batch[address + 4u], program_evidence_batch[address + 5u],
            program_evidence_batch[address + 6u], program_evidence_batch[address + 7u]);
    }
    return true;
}
public bool pev_read_root(uint root, out uint2 value)
{ return pev_read2(7u, root, 0u, value); }
public bool pev_scalar_is_valid(uint scalar)
{
    // One shared checked identity domain. Native execution support is a
    // separate target contract, never a reason to alias primitive identities.
    return scalar_is_known(scalar);
}

// Reject overlapping physical input table slices, including header/directories.
// This is fixed 18*18 work, independent of program graph size.
public EvidenceStatus pev_admit_directories()
{
    uint actual_catalog; uint actual_batch; uint stride;
    program_evidence_catalog.GetDimensions(actual_catalog, stride);
    program_evidence_batch.GetDimensions(actual_batch, stride);
    if (program_evidence_params.catalog_word_count > actual_catalog)
        return pev_limit(20u, 0u, program_evidence_params.catalog_word_count, actual_catalog);
    if (program_evidence_params.batch_word_count > actual_batch)
        return pev_limit(20u, 1u, program_evidence_params.batch_word_count, actual_batch);
    if (!pev_header_is_valid()) return pev_invalid(1u, PEV_INVALID, PEV_INVALID);
    uint batch_header_end = PEV_BATCH_FIXED_WORDS;
    for (uint table = 0u; table < PEV_TABLES; table++)
    {
        EvidenceTable current;
        // Header admission made this fixed directory read safe. Preserve the
        // allocation failure separately from an invalid pointer/row encoding.
        uint directory = PEV_DIRECTORY_WORD + table * 6u;
        uint used = program_evidence_batch[directory + 3u];
        uint capacity = program_evidence_batch[directory + 4u];
        if (used > capacity) return pev_limit(20u, table, used, capacity);
        uint offset = program_evidence_batch[directory + 2u];
        uint width = program_evidence_batch[directory + 5u];
        if (width == pev_expected_width(table) && offset <= program_evidence_params.batch_word_count)
        {
            uint available = (program_evidence_params.batch_word_count - offset) / width;
            if (capacity > available) return pev_limit(20u, table, capacity, available);
        }
        if (!pev_descriptor(table, current)) return pev_invalid(1u, table, PEV_INVALID);
        if ((current.catalog_count != 0u && current.catalog_offset < 4u) ||
            (current.batch_capacity != 0u && current.batch_offset < batch_header_end))
            return pev_invalid(1u, table, PEV_INVALID);
        uint catalog_end = current.catalog_offset + current.catalog_count * current.width;
        uint batch_end = current.batch_offset + current.batch_capacity * current.width;
        for (uint prior = 0u; prior < table; prior++)
        {
            EvidenceTable other;
            if (!pev_descriptor(prior, other)) return pev_invalid(1u, prior, PEV_INVALID);
            if (current.catalog_count != 0u && other.catalog_count != 0u &&
                current.catalog_offset < other.catalog_offset + other.catalog_count * other.width &&
                other.catalog_offset < catalog_end) return pev_invalid(1u, table, prior);
            if (current.batch_capacity != 0u && other.batch_capacity != 0u &&
                current.batch_offset < other.batch_offset + other.batch_capacity * other.width &&
                other.batch_offset < batch_end) return pev_invalid(1u, table, prior);
        }
    }
    return pev_ok();
}
