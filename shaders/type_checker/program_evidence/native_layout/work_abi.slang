import type_checker.program_evidence.abi;
// One exclusive, unpublished layout job. This arena never authorizes a method
// call or a proof: its eventual result is bound to the exact owned term input.
import type_checker.program_evidence.native_layout.recipe_abi;
import type_checker.program_evidence.proof_store_abi;

public static const uint PLM_MAGIC = 0x504c4d31u;
public static const uint PLM_VERSION = 2u;
public static const uint PLM_DIRECTORY = 24u;
public static const uint PLM_TABLES = 7u;
public static const uint PLM_FIXED_WORDS = PLM_DIRECTORY + PLM_TABLES * 3u;
public RWStructuredBuffer<uint> program_evidence_native_layout_work;

// The binding covers the retained allocation; the dispatch parameters carry
// the logical extent. A logical extent beyond the allocation reads as empty.
public uint plm_logical_words()
{
    uint physical; uint stride;
    program_evidence_native_layout_work.GetDimensions(physical, stride);
    uint logical = program_evidence_params.work_word_count;
    return select(logical <= physical, logical, 0u);
}

// Row widths, one nibble per table (low nibble first): 8,2,2,2,4,8,4; else 0.
// Readers are straight-line selects with one guarded early return.
[ForceInline]
public uint plm_width(uint table)
{
    return (0x04842228u >> (select(table < PLM_TABLES, table, 7u) * 4u)) & 15u;
}
public bool plm_table(uint table, out uint offset, out uint capacity)
{
    offset = PEV_INVALID; capacity = 0u; uint actual = plm_logical_words();
    if (!((table < PLM_TABLES) & (actual >= PLM_FIXED_WORDS))) return false;
    uint logical = program_evidence_native_layout_work[12u];
    uint base = PLM_DIRECTORY + table * 3u;
    uint read_offset = program_evidence_native_layout_work[base];
    uint read_capacity = program_evidence_native_layout_work[base + 1u];
    offset = read_offset; capacity = read_capacity;
    uint width = plm_width(table);
    return (logical == actual) & (program_evidence_native_layout_work[base + 2u] == width) &
        (read_capacity != PEV_INVALID) & ((read_capacity != 0u) | (read_offset == 0u)) &
        pev_word_span(read_offset, read_capacity, width, logical);
}
public uint plm_used(uint table)
{
    if (table > 4u) return select(table < PLM_TABLES, 1u, 0u);
    return program_evidence_native_layout_work[13u + select(table < 4u, table, 0u)];
}
public bool plm_address(uint table, uint row, uint field, uint fields, bool pending, out uint address)
{
    address = PEV_INVALID; uint offset; uint capacity;
    bool known = plm_table(table, offset, capacity);
    uint width = plm_width(table);
    if (!(known & (fields != 0u) & (field < width) & (fields <= width - field) & (row < capacity)))
        return false;
    // A successful table read proves the fixed used-count words exist.
    if (!pending && row >= plm_used(table)) return false;
    address = offset + row * width + field; return true;
}
public bool plm_read2(uint table, uint row, uint field, bool pending, out uint2 value)
{
    value = uint2(PEV_INVALID, PEV_INVALID); uint address;
    if (!plm_address(table, row, field, 2u, pending, address)) return false;
    value = uint2(program_evidence_native_layout_work[address], program_evidence_native_layout_work[address + 1u]);
    return true;
}
public bool plm_read4(uint table, uint row, uint field, bool pending, out uint4 value)
{
    value = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); uint address;
    if (!plm_address(table, row, field, 4u, pending, address)) return false;
    value = uint4(program_evidence_native_layout_work[address], program_evidence_native_layout_work[address + 1u],
        program_evidence_native_layout_work[address + 2u], program_evidence_native_layout_work[address + 3u]);
    return true;
}
// One address check for a complete eight-word row (fields 0..7).
public bool plm_read8(uint table, uint row, bool pending, out uint4 low, out uint4 high)
{
    low = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); high = low; uint address;
    if (!plm_address(table, row, 0u, 8u, pending, address)) return false;
    low = uint4(program_evidence_native_layout_work[address], program_evidence_native_layout_work[address + 1u],
        program_evidence_native_layout_work[address + 2u], program_evidence_native_layout_work[address + 3u]);
    high = uint4(program_evidence_native_layout_work[address + 4u], program_evidence_native_layout_work[address + 5u],
        program_evidence_native_layout_work[address + 6u], program_evidence_native_layout_work[address + 7u]);
    return true;
}
public bool plm_write2(uint table, uint row, uint field, uint2 value)
{
    uint address;
    if (!plm_address(table, row, field, 2u, true, address)) return false;
    program_evidence_native_layout_work[address] = value.x;
    program_evidence_native_layout_work[address + 1u] = value.y; return true;
}
public bool plm_write4(uint table, uint row, uint field, uint4 value)
{
    uint address;
    if (!plm_address(table, row, field, 4u, true, address)) return false;
    program_evidence_native_layout_work[address] = value.x;
    program_evidence_native_layout_work[address + 1u] = value.y;
    program_evidence_native_layout_work[address + 2u] = value.z;
    program_evidence_native_layout_work[address + 3u] = value.w; return true;
}
public bool plm_header_is_valid()
{
    uint actual = plm_logical_words();
    if (actual < PLM_FIXED_WORDS || !plr_is_valid() || !pps_identity_is_valid() ||
        program_evidence_proof_store[7u] != proof_store_params.serial ||
        program_evidence_proof_store[10u] != PEV_VALID) return false;
    if (program_evidence_native_layout_work[0u] != PLM_MAGIC ||
        program_evidence_native_layout_work[1u] != PLM_VERSION ||
        program_evidence_native_layout_work[2u] != proof_store_params.epoch_low ||
        program_evidence_native_layout_work[3u] != proof_store_params.epoch_high ||
        program_evidence_native_layout_work[2u] != program_evidence_catalog[2u] ||
        program_evidence_native_layout_work[3u] != program_evidence_catalog[3u] ||
        program_evidence_native_layout_work[4u] != proof_store_params.arena_low ||
        program_evidence_native_layout_work[5u] != proof_store_params.arena_high ||
        program_evidence_native_layout_work[6u] != proof_store_params.serial ||
        program_evidence_native_layout_work[7u] != 0u ||
        program_evidence_native_layout_work[10u] != 0u ||
        program_evidence_native_layout_work[11u] != 0u ||
        program_evidence_native_layout_work[17u] == 0u) return false;
    for (uint reserved = 21u; reserved < PLM_DIRECTORY; reserved++)
        if (program_evidence_native_layout_work[reserved] != 0u) return false;
    uint next = PLM_FIXED_WORDS; uint nodes = 0u;
    for (uint table = 0u; table < PLM_TABLES; table++)
    {
        uint offset; uint capacity;
        if (!plm_table(table, offset, capacity) || (capacity != 0u && offset != next) ||
            plm_used(table) > capacity) return false;
        if (table == 0u) nodes = capacity;
        if ((table == 4u && capacity != nodes) || (table >= 5u && capacity != 1u)) return false;
        next += capacity * plm_width(table);
    }
    return next == actual && program_evidence_native_layout_work[18u] <= program_evidence_native_layout_work[17u];
}
public EvidenceStatus plm_charge(uint visits)
{
    uint used = program_evidence_native_layout_work[18u];
    uint limit = program_evidence_native_layout_work[17u];
    if (used > limit || visits > limit - used)
        return pev_limit(170u, PEV_INVALID, visits, used <= limit ? limit - used : 0u);
    program_evidence_native_layout_work[18u] = used + visits; return pev_ok();
}
public EvidenceStatus plm_reserve(uint table, uint count, out uint first)
{
    first = PEV_INVALID; uint offset; uint capacity;
    if (table >= 4u || !plm_table(table, offset, capacity)) return pev_invalid(171u, table, PEV_INVALID);
    uint used = plm_used(table);
    if (used > capacity || count > capacity - used)
        return pev_limit(172u, table, count, used <= capacity ? capacity - used : 0u);
    first = used; return pev_ok();
}
public void plm_status(EvidenceStatus status)
{
    // Single writer; publication happens only after complete graph/layout checks.
    plm_write4(5u, 0u, 4u, uint4(status.required, status.available, 0u, 0u));
    plm_write4(5u, 0u, 0u, uint4(status.state, status.detail, status.subject_row, status.related_row));
}
