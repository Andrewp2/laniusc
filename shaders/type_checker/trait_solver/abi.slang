import primitive_types;
import thread_scratch;
// Every address is checked before dereference. Logical row IDs span a frozen
// catalog prefix followed by a retained batch suffix; capacity is not identity.
public static const uint TS_INVALID = 0xffffffffu;
public static const uint TS_MAGIC = 0x50455631u;
public static const uint TS_VERSION = 3u;
public static const uint TS_TABLES = 18u;
public static const uint TS_OUTPUT_TABLES = 13u;
public static const uint TS_DIRECTORY_WORD = 8u;
public static const uint TS_OUTPUT_DIRECTORY_WORD = TS_DIRECTORY_WORD + TS_TABLES * 6u;
public static const uint TS_BATCH_FIXED_WORDS = TS_OUTPUT_DIRECTORY_WORD + TS_OUTPUT_TABLES * 5u;
public static const uint TS_VALID = 1u;
public static const uint TS_INVALID_INPUT = 2u;
public static const uint TS_RESOURCE_LIMIT = 3u;
public static const uint TS_UNSUPPORTED = 4u;
public static const uint TS_COHERENCE_CONFLICT = 5u;
public static const uint TS_OBLIGATION_FAILURE = 6u;
public static const uint TS_DEPTH_LIMIT = 64u;
public static const uint TS_VISIT_LIMIT = 65536u;

public struct EvidenceStatus
{
    public uint state; public uint detail; public uint subject_row; public uint related_row;
    public uint required; public uint available;
}
// The status helpers below inline this constructor at every return site.
[ForceInline]
public EvidenceStatus ts_status(uint state, uint detail, uint subject, uint related,
    uint required, uint available)
{
    EvidenceStatus r;
    r.state = state; r.detail = detail; r.subject_row = subject; r.related_row = related;
    r.required = required; r.available = available;
    return r;
}
[ForceInline]
public EvidenceStatus ts_ok()
{ return ts_status(TS_VALID, 0u, TS_INVALID, TS_INVALID, 0u, 0u); }
[ForceInline]
public EvidenceStatus ts_invalid(uint detail, uint subject, uint related)
{ return ts_status(TS_INVALID_INPUT, detail, subject, related, 0u, 0u); }
[ForceInline]
public EvidenceStatus ts_limit(uint detail, uint subject, uint required, uint available)
{ return ts_status(TS_RESOURCE_LIMIT, detail, subject, TS_INVALID, required, available); }
// A row that reaches the thread-scratch walkers binds its dispatch-local slot
// first. Without a slot it must report `missing` instead of running.
public bool ts_bind_scratch(uint local, uint subject, out EvidenceStatus missing)
{
    uint slots = thread_scratch_begin(local);
    missing = ts_limit(190u, subject, local + 1u, slots);
    return local < slots;
}
public struct TraitSolverParams
{
    public uint dispatch_first; public uint dispatch_count; public uint catalog_word_count; public uint batch_word_count;
    public uint output_word_count; public uint phase;
    // Logical extents of the native-layout sidecars (0 when not bound). Those
    // arenas bind their whole retained allocation; see plr/plm_logical_words.
    public uint recipe_word_count; public uint work_word_count;
}
public ConstantBuffer<TraitSolverParams> trait_solver_params;
// One resource binding avoids overlapping RO/RW aliases during catalog build.
// After the freeze phase the dispatcher binds this arena read-only in policy;
// later entry points never call a catalog writer.
public RWStructuredBuffer<uint> trait_solver_catalog;
public StructuredBuffer<uint> trait_solver_batch;
public RWStructuredBuffer<uint> trait_solver_output;

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
public uint ts_expected_width(uint table)
{
    uint packed = select(table < 8u, 0x22844984u, select(table < 16u, 0x868456C8u, 0x00000084u));
    return select(table < TS_TABLES, (packed >> ((table & 7u) * 4u)) & 15u, 0u);
}
// Division by a selected nonzero width never changes a result whose width
// term is false; it only keeps the expression free of a branch.
[ForceInline]
public uint ts_rows_in(uint offset, uint words, uint width)
{ return (words - offset) / select(width == 0u, 1u, width); }
[ForceInline]
public bool ts_word_span(uint offset, uint rows, uint width, uint words)
{
    return (width != 0u) & (offset <= words) & (rows <= ts_rows_in(offset, words, width));
}

// This small fixed header check is safe even when the logical lengths are bad.
public bool ts_header_is_valid()
{
    uint catalog_words; uint catalog_stride; uint batch_words; uint batch_stride;
    trait_solver_catalog.GetDimensions(catalog_words, catalog_stride);
    trait_solver_batch.GetDimensions(batch_words, batch_stride);
    uint c = trait_solver_params.catalog_word_count;
    uint b = trait_solver_params.batch_word_count;
    if (c < 4u || b < TS_BATCH_FIXED_WORDS || c > catalog_words || b > batch_words)
        return false;
    if (trait_solver_catalog[0u] != TS_MAGIC ||
        trait_solver_catalog[1u] != TS_VERSION ||
        trait_solver_batch[0u] != TS_MAGIC ||
        trait_solver_batch[1u] != TS_VERSION ||
        trait_solver_catalog[2u] != trait_solver_batch[2u] ||
        trait_solver_catalog[3u] != trait_solver_batch[3u] ||
        trait_solver_batch[5u] != TS_TABLES ||
        trait_solver_batch[6u] != TS_DIRECTORY_WORD ||
        trait_solver_batch[7u] != TS_OUTPUT_DIRECTORY_WORD)
        return false;
    return true;
}

public bool ts_descriptor(uint table, out EvidenceTable desc)
{
    desc = (EvidenceTable)0;
    // Protocol identity is checked by initialization/work/publication gates.
    // This reader independently proves physical safety; no cached admission or
    // capacity value substitutes for logical row membership.
    uint actual_catalog; uint actual_batch; uint stride;
    trait_solver_catalog.GetDimensions(actual_catalog, stride);
    trait_solver_batch.GetDimensions(actual_batch, stride);
    uint catalog_words = trait_solver_params.catalog_word_count;
    uint batch_words = trait_solver_params.batch_word_count;
    if (!((table < TS_TABLES) & (catalog_words >= 4u) & (batch_words >= TS_BATCH_FIXED_WORDS) &
        (catalog_words <= actual_catalog) & (batch_words <= actual_batch))) return false;
    // table < TS_TABLES and the fixed header bound prove all six words.
    uint start = TS_DIRECTORY_WORD + table * 6u;
    EvidenceTable read = {
        trait_solver_batch[start], trait_solver_batch[start + 1u],
        trait_solver_batch[start + 2u], trait_solver_batch[start + 3u],
        trait_solver_batch[start + 4u], trait_solver_batch[start + 5u] };
    desc = read;
    // Tables 0,2,3,4,8,9,10 are catalog-only; tables from 11 are batch-only.
    bool catalog_only = ((0x71Du >> (table & 31u)) & 1u) != 0u;
    bool batch_only = table >= 11u;
    return (read.width == ts_expected_width(table)) &
        (read.batch_count <= read.batch_capacity) & (read.batch_count != TS_INVALID) &
        (read.catalog_count <= TS_INVALID - 1u - read.batch_count) &
        ((read.catalog_count != 0u) | (read.catalog_offset == 0u)) &
        ((read.batch_capacity != 0u) | (read.batch_offset == 0u)) &
        ts_word_span(read.catalog_offset, read.catalog_count, read.width, catalog_words) &
        ts_word_span(read.batch_offset, read.batch_capacity, read.width, batch_words) &
        (!catalog_only | (read.batch_capacity == 0u)) & (!batch_only | (read.catalog_count == 0u));
}

// This is a safe directory projection, not descriptor admission. Initialization
// validates every table's width, arena domain, capacity, complete extents and
// disjointness before any work phase. The input directory then stays immutable.
// Counts alone are also used to derive output sizes during initialization; that
// initializer still requires full descriptor admission before any table writer.
public bool ts_input_table_rows(uint table, out uint directory,
    out uint catalog_count, out uint batch_count)
{
    directory = TS_INVALID; catalog_count = 0u; batch_count = 0u;
    uint actual_batch; uint stride;
    trait_solver_batch.GetDimensions(actual_batch, stride);
    uint batch_words = trait_solver_params.batch_word_count;
    if (!((table < TS_TABLES) & (batch_words >= TS_BATCH_FIXED_WORDS) &
        (batch_words <= actual_batch))) return false;
    uint start = TS_DIRECTORY_WORD + table * 6u;
    uint prefix = trait_solver_batch[start + 1u];
    uint suffix = trait_solver_batch[start + 3u];
    if (!((suffix != TS_INVALID) & (prefix <= TS_INVALID - 1u - suffix))) return false;
    directory = start; catalog_count = prefix; batch_count = suffix;
    return true;
}
public bool ts_table_count(uint table, out uint count)
{
    count = 0u;
    uint directory; uint catalog_count; uint batch_count;
    if (!ts_input_table_rows(table, directory, catalog_count, batch_count)) return false;
    count = catalog_count + batch_count;
    return true;
}
public bool ts_row_span(uint table, uint first, uint count)
{
    uint total;
    bool known = ts_table_count(table, total);
    return known & (first <= total) & (count <= total - first);
}
// Independent address safety does not require re-admitting unrelated rows or
// the other arena's full table capacity. The fixed ABI width and exact logical
// prefix/suffix select one row, whose entire extent must fit in the logical and
// actual selected buffer before any address multiplication or addition.
// The directory guard is the only branch: it makes the fixed directory reads
// safe; every remaining condition is pure and combined without short-circuit.
public bool ts_read_address(uint table, uint row, uint first_field, uint fields,
    out uint arena, out uint address)
{
    arena = TS_INVALID; address = TS_INVALID;
    uint actual_catalog; uint actual_batch; uint stride;
    trait_solver_catalog.GetDimensions(actual_catalog, stride);
    trait_solver_batch.GetDimensions(actual_batch, stride);
    uint batch_words = trait_solver_params.batch_word_count;
    if (!((table < TS_TABLES) & (batch_words >= TS_BATCH_FIXED_WORDS) &
        (batch_words <= actual_batch))) return false;
    uint start = TS_DIRECTORY_WORD + table * 6u;
    uint catalog_count = trait_solver_batch[start + 1u];
    uint batch_count = trait_solver_batch[start + 3u];
    uint width = ts_expected_width(table);
    bool in_catalog = row < catalog_count;
    uint local = select(in_catalog, row, row - catalog_count);
    uint offset = trait_solver_batch[start + select(in_catalog, 0u, 2u)];
    uint words = select(in_catalog, trait_solver_params.catalog_word_count, batch_words);
    uint actual = select(in_catalog, actual_catalog, actual_batch);
    // width is nonzero for every admitted table ID. Division avoids overflow
    // even for arbitrary malformed offsets/counts, without trusting capacity.
    if (!((batch_count != TS_INVALID) & (catalog_count <= TS_INVALID - 1u - batch_count) &
        (fields != 0u) & (first_field < width) & (fields <= width - first_field) &
        (in_catalog | (local < batch_count)) & (words <= actual) & (offset <= words) &
        (local < ts_rows_in(offset, words, width)))) return false;
    arena = select(in_catalog, 0u, 1u); address = offset + local * width + first_field;
    return true;
}
public bool ts_word(uint table, uint row, uint field, out uint value)
{
    value = TS_INVALID; uint arena; uint address;
    if (!ts_read_address(table, row, field, 1u, arena, address)) return false;
    if (arena == 0u) value = trait_solver_catalog[address];
    else value = trait_solver_batch[address];
    return true;
}
public bool ts_read2(uint table, uint row, uint first_field, out uint2 value)
{
    value = uint2(TS_INVALID, TS_INVALID); uint arena; uint address;
    if (!ts_read_address(table, row, first_field, 2u, arena, address)) return false;
    // Preserve scalar storage addressing: packed rows need not be vector aligned.
    if (arena == 0u)
        value = uint2(trait_solver_catalog[address], trait_solver_catalog[address + 1u]);
    else
        value = uint2(trait_solver_batch[address], trait_solver_batch[address + 1u]);
    return true;
}
public bool ts_read4(uint table, uint row, uint first_field, out uint4 value)
{
    value = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID); uint arena; uint address;
    if (!ts_read_address(table, row, first_field, 4u, arena, address)) return false;
    if (arena == 0u)
        value = uint4(trait_solver_catalog[address], trait_solver_catalog[address + 1u],
            trait_solver_catalog[address + 2u], trait_solver_catalog[address + 3u]);
    else
        value = uint4(trait_solver_batch[address], trait_solver_batch[address + 1u],
            trait_solver_batch[address + 2u], trait_solver_batch[address + 3u]);
    return true;
}
public bool ts_read8(uint table, uint row, out uint4 low, out uint4 high)
{
    low = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID); high = low;
    uint arena; uint address;
    if (!ts_read_address(table, row, 0u, 8u, arena, address)) return false;
    if (arena == 0u)
    {
        low = uint4(trait_solver_catalog[address], trait_solver_catalog[address + 1u],
            trait_solver_catalog[address + 2u], trait_solver_catalog[address + 3u]);
        high = uint4(trait_solver_catalog[address + 4u], trait_solver_catalog[address + 5u],
            trait_solver_catalog[address + 6u], trait_solver_catalog[address + 7u]);
    }
    else
    {
        low = uint4(trait_solver_batch[address], trait_solver_batch[address + 1u],
            trait_solver_batch[address + 2u], trait_solver_batch[address + 3u]);
        high = uint4(trait_solver_batch[address + 4u], trait_solver_batch[address + 5u],
            trait_solver_batch[address + 6u], trait_solver_batch[address + 7u]);
    }
    return true;
}
public bool ts_read_root(uint root, out uint2 value)
{ return ts_read2(7u, root, 0u, value); }
public bool ts_scalar_is_valid(uint scalar)
{
    // One shared checked identity domain. Native execution support is a
    // separate target contract, never a reason to alias primitive identities.
    return scalar_is_known(scalar);
}

// Reject overlapping physical input table slices, including header/directories.
// This is fixed 18*18 work, independent of program graph size.
public EvidenceStatus ts_admit_directories()
{
    uint actual_catalog; uint actual_batch; uint stride;
    trait_solver_catalog.GetDimensions(actual_catalog, stride);
    trait_solver_batch.GetDimensions(actual_batch, stride);
    if (trait_solver_params.catalog_word_count > actual_catalog)
        return ts_limit(20u, 0u, trait_solver_params.catalog_word_count, actual_catalog);
    if (trait_solver_params.batch_word_count > actual_batch)
        return ts_limit(20u, 1u, trait_solver_params.batch_word_count, actual_batch);
    if (!ts_header_is_valid()) return ts_invalid(1u, TS_INVALID, TS_INVALID);
    uint batch_header_end = TS_BATCH_FIXED_WORDS;
    for (uint table = 0u; table < TS_TABLES; table++)
    {
        EvidenceTable current;
        // Header admission made this fixed directory read safe. Preserve the
        // allocation failure separately from an invalid pointer/row encoding.
        uint directory = TS_DIRECTORY_WORD + table * 6u;
        uint used = trait_solver_batch[directory + 3u];
        uint capacity = trait_solver_batch[directory + 4u];
        if (used > capacity) return ts_limit(20u, table, used, capacity);
        uint offset = trait_solver_batch[directory + 2u];
        uint width = trait_solver_batch[directory + 5u];
        if (width == ts_expected_width(table) && offset <= trait_solver_params.batch_word_count)
        {
            uint available = (trait_solver_params.batch_word_count - offset) / width;
            if (capacity > available) return ts_limit(20u, table, capacity, available);
        }
        if (!ts_descriptor(table, current)) return ts_invalid(1u, table, TS_INVALID);
        if ((current.catalog_count != 0u && current.catalog_offset < 4u) ||
            (current.batch_capacity != 0u && current.batch_offset < batch_header_end))
            return ts_invalid(1u, table, TS_INVALID);
        uint catalog_end = current.catalog_offset + current.catalog_count * current.width;
        uint batch_end = current.batch_offset + current.batch_capacity * current.width;
        for (uint prior = 0u; prior < table; prior++)
        {
            EvidenceTable other;
            if (!ts_descriptor(prior, other)) return ts_invalid(1u, prior, TS_INVALID);
            if (current.catalog_count != 0u && other.catalog_count != 0u &&
                current.catalog_offset < other.catalog_offset + other.catalog_count * other.width &&
                other.catalog_offset < catalog_end) return ts_invalid(1u, table, prior);
            if (current.batch_capacity != 0u && other.batch_capacity != 0u &&
                current.batch_offset < other.batch_offset + other.batch_capacity * other.width &&
                other.batch_offset < batch_end) return ts_invalid(1u, table, prior);
        }
    }
    return ts_ok();
}
