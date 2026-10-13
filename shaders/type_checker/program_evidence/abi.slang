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
public EvidenceStatus pev_ok()
{
    EvidenceStatus r = { PEV_VALID, 0u, PEV_INVALID, PEV_INVALID, 0u, 0u };
    return r;
}
public EvidenceStatus pev_invalid(uint detail, uint subject, uint related)
{
    EvidenceStatus r = { PEV_INVALID_INPUT, detail, subject, related, 0u, 0u };
    return r;
}
public EvidenceStatus pev_limit(uint detail, uint subject, uint required, uint available)
{
    EvidenceStatus r = { PEV_RESOURCE_LIMIT, detail, subject, PEV_INVALID, required, available };
    return r;
}
public struct ProgramEvidenceParams
{
    public uint dispatch_first; public uint dispatch_count; public uint catalog_word_count; public uint batch_word_count;
    public uint output_word_count; public uint phase; public uint reserved0; public uint reserved1;
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

public uint pev_expected_width(uint table)
{
    switch (table)
    {
    case 0u: return 4u; case 1u: return 8u; case 2u: return 9u;
    case 3u: return 4u; case 4u: return 4u; case 5u: return 8u;
    case 6u: return 2u; case 7u: return 2u; case 8u: return 8u;
    case 9u: return 12u; case 10u: return 6u; case 11u: return 5u;
    case 12u: return 4u; case 13u: return 8u; case 14u: return 6u;
    case 15u: return 8u; case 16u: return 4u; case 17u: return 8u;
    default: return 0u;
    }
}
public bool pev_word_span(uint offset, uint rows, uint width, uint words)
{
    return width != 0u && offset <= words && rows <= (words - offset) / width;
}

// This small fixed header check is safe even when the logical lengths are bad.
public bool pev_header_is_valid()
{
    uint catalog_words; uint catalog_stride; uint batch_words; uint batch_stride;
    program_evidence_catalog.GetDimensions(catalog_words, catalog_stride);
    program_evidence_batch.GetDimensions(batch_words, batch_stride);
    uint c = program_evidence_params.catalog_word_count;
    uint b = program_evidence_params.batch_word_count;
    if (c < 4u || b < PEV_BATCH_FIXED_WORDS || c > catalog_words || b > batch_words ||
        program_evidence_params.reserved0 != 0u || program_evidence_params.reserved1 != 0u)
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
    if (table >= PEV_TABLES) return false;
    // Protocol identity is checked by initialization/work/publication gates.
    // This reader independently proves physical safety; no cached admission or
    // capacity value substitutes for logical row membership.
    uint actual_catalog; uint actual_batch; uint stride;
    program_evidence_catalog.GetDimensions(actual_catalog, stride);
    program_evidence_batch.GetDimensions(actual_batch, stride);
    uint catalog_words = program_evidence_params.catalog_word_count;
    uint batch_words = program_evidence_params.batch_word_count;
    if (catalog_words < 4u || batch_words < PEV_BATCH_FIXED_WORDS ||
        catalog_words > actual_catalog || batch_words > actual_batch) return false;
    // table < PEV_TABLES and the fixed header bound prove all six words.
    uint start = PEV_DIRECTORY_WORD + table * 6u;
    desc.catalog_offset = program_evidence_batch[start];
    desc.catalog_count = program_evidence_batch[start + 1u];
    desc.batch_offset = program_evidence_batch[start + 2u];
    desc.batch_count = program_evidence_batch[start + 3u];
    desc.batch_capacity = program_evidence_batch[start + 4u];
    desc.width = program_evidence_batch[start + 5u];
    if (desc.width != pev_expected_width(table) ||
        desc.batch_count > desc.batch_capacity ||
        desc.batch_count == PEV_INVALID ||
        desc.catalog_count > PEV_INVALID - 1u - desc.batch_count ||
        (desc.catalog_count == 0u && desc.catalog_offset != 0u) ||
        (desc.batch_capacity == 0u && desc.batch_offset != 0u) ||
        !pev_word_span(desc.catalog_offset, desc.catalog_count, desc.width,
            program_evidence_params.catalog_word_count) ||
        !pev_word_span(desc.batch_offset, desc.batch_capacity, desc.width,
            program_evidence_params.batch_word_count)) return false;
    bool catalog_only = table == 0u || table == 2u || table == 3u || table == 4u ||
        table == 8u || table == 9u || table == 10u;
    bool batch_only = table >= 11u;
    return (!catalog_only || desc.batch_capacity == 0u) &&
        (!batch_only || desc.catalog_count == 0u);
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
    if (table >= PEV_TABLES) return false;
    uint actual_batch; uint stride;
    program_evidence_batch.GetDimensions(actual_batch, stride);
    uint batch_words = program_evidence_params.batch_word_count;
    if (batch_words < PEV_BATCH_FIXED_WORDS || batch_words > actual_batch) return false;
    uint start = PEV_DIRECTORY_WORD + table * 6u;
    uint prefix = program_evidence_batch[start + 1u];
    uint suffix = program_evidence_batch[start + 3u];
    if (suffix == PEV_INVALID || prefix > PEV_INVALID - 1u - suffix) return false;
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
    return pev_table_count(table, total) && first <= total && count <= total - first;
}
// Independent address safety does not require re-admitting unrelated rows or
// the other arena's full table capacity. The fixed ABI width and exact logical
// prefix/suffix select one row, whose entire extent must fit in the logical and
// actual selected buffer before any address multiplication or addition.
public bool pev_read_address(uint table, uint row, uint first_field, uint fields,
    out uint arena, out uint address)
{
    arena = PEV_INVALID; address = PEV_INVALID;
    uint directory; uint catalog_count; uint batch_count;
    if (!pev_input_table_rows(table, directory, catalog_count, batch_count)) return false;
    uint width = pev_expected_width(table);
    if (fields == 0u || first_field >= width || fields > width - first_field) return false;
    uint selected_arena; uint offset; uint local; uint words; uint actual; uint stride;
    if (row < catalog_count)
    {
        selected_arena = 0u; local = row;
        offset = program_evidence_batch[directory];
        words = program_evidence_params.catalog_word_count;
        program_evidence_catalog.GetDimensions(actual, stride);
    }
    else
    {
        selected_arena = 1u; local = row - catalog_count;
        if (local >= batch_count) return false;
        offset = program_evidence_batch[directory + 2u];
        words = program_evidence_params.batch_word_count;
        program_evidence_batch.GetDimensions(actual, stride);
    }
    // width is nonzero for every admitted table ID. Division avoids overflow
    // even for arbitrary malformed offsets/counts, without trusting capacity.
    if (words > actual || offset > words || local >= (words - offset) / width) return false;
    arena = selected_arena; address = offset + local * width + first_field;
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
