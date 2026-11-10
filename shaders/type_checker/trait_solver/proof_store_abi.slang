// Owned solver storage. This is separate from appendable input Node5 IDs and
// from the source-obligation-sized output directory. Every logical table is a
// slice of one packet-owned RW arena; there is no allocation per table or root.
import type_checker.trait_solver.abi;

public static const uint PPS_MAGIC = 0x50505332u;
public static const uint PPS_VERSION = 4u;
public static const uint PPS_TABLES = 16u;
public static const uint PPS_DIRECTORY = 12u;
public static const uint PPS_FIXED_WORDS = PPS_DIRECTORY + PPS_TABLES * 6u;
public static const uint PPS_PERSISTENT_TABLES = 8u;
public static const uint PPS_BUILDING = 0xfffffffeu;
public static const uint PPS_TERM_NODES = 0u;
public static const uint PPS_TERM_EDGES = 1u;
public static const uint PPS_TERM_ROOTS = 2u;
public static const uint PPS_GOALS = 3u;
public static const uint PPS_SUBSTITUTIONS = 4u;
public static const uint PPS_BINDINGS = 5u;
public static const uint PPS_PROOFS = 6u;
public static const uint PPS_PROOF_EDGES = 7u;
public static const uint PPS_WORK = 8u;
public static const uint PPS_REQUIREMENTS = 9u;
public static const uint PPS_GOAL_INDEX = 10u;
public static const uint PPS_GOAL_BUCKETS = 11u;
public static const uint PPS_FRONTIER = 12u;
public static const uint PPS_ROOT_LINKS = 13u;
public static const uint PPS_NORMALIZATION_REQUESTS = 14u;
public static const uint PPS_REDUCTION_QUEUE = 15u;

public struct ProofStoreParams
{
    public uint word_count; public uint epoch_low; public uint epoch_high; public uint arena_low;
    public uint arena_high; public uint serial; public uint phase; public uint reserved;
}
public ConstantBuffer<ProofStoreParams> proof_store_params;
public RWStructuredBuffer<uint> trait_solver_proof_store;

// Directory6: physical offset, reserved logical rows, physical row capacity,
// admitted logical prefix, accepted logical prefix, fixed row width.
// Reservation alone authorizes no read. Stage admission advances field3 only
// after every reserved row has been emitted and checked. Receipt publication
// advances field4 only after every original obligation succeeds.
// Every width is a power of two: log2 per table, one nibble each (low nibble
// first): tables0-7 3,1,1,3,2,3,3,2; tables8-15 4,2,2,0,1,1,3,1; else 0.
// Readers below are straight-line selects with one guarded early return.
[ForceInline]
public uint pps_width(uint table)
{
    uint shift = (select(table < 8u, 0x23323113u, 0x13110224u) >> ((table & 7u) * 4u)) & 15u;
    return select(table < PPS_TABLES, 1u << shift, 0u);
}
[ForceInline]
public bool pps_physical_header()
{
    uint actual; uint stride;
    trait_solver_proof_store.GetDimensions(actual, stride);
    return (proof_store_params.word_count >= PPS_FIXED_WORDS) &
        (proof_store_params.word_count <= actual);
}
public bool pps_identity_is_valid()
{
    if (!(pps_physical_header() & (proof_store_params.reserved == 0u) &
        (proof_store_params.serial != 0u) & (proof_store_params.serial != TS_INVALID))) return false;
    return (trait_solver_proof_store[0u] == PPS_MAGIC) &
        (trait_solver_proof_store[1u] == PPS_VERSION) &
        (trait_solver_proof_store[2u] == proof_store_params.epoch_low) &
        (trait_solver_proof_store[3u] == proof_store_params.epoch_high) &
        (trait_solver_proof_store[4u] == proof_store_params.arena_low) &
        (trait_solver_proof_store[5u] == proof_store_params.arena_high) &
        (trait_solver_proof_store[6u] == proof_store_params.serial) &
        (trait_solver_proof_store[8u] == PPS_TABLES) &
        (trait_solver_proof_store[9u] == PPS_DIRECTORY) &
        (trait_solver_proof_store[11u] == 0u);
}
public bool pps_building()
{
    return pps_identity_is_valid() && trait_solver_proof_store[10u] == PPS_BUILDING;
}
public bool pps_descriptor(uint table, out uint4 span, out uint accepted)
{
    span = uint4(0u, 0u, 0u, 0u); accepted = 0u;
    if (!((table < PPS_TABLES) & pps_physical_header())) return false;
    uint directory = PPS_DIRECTORY + table * 6u;
    uint4 read = uint4(trait_solver_proof_store[directory],
        trait_solver_proof_store[directory + 1u],
        trait_solver_proof_store[directory + 2u],
        trait_solver_proof_store[directory + 3u]);
    uint read_accepted = trait_solver_proof_store[directory + 4u];
    span = read; accepted = read_accepted;
    uint width = pps_width(table);
    return (trait_solver_proof_store[directory + 5u] == width) &
        (read.y != TS_INVALID) & (read_accepted <= read.w) & (read.w <= read.y) & (read.y <= read.z) &
        ((table < PPS_PERSISTENT_TABLES) | (read_accepted == 0u)) &
        select(read.z == 0u, read.x == 0u, read.x >= PPS_FIXED_WORDS) &
        ts_word_span(read.x, read.z, width, proof_store_params.word_count);
}
// init is the only complete directory/overlap admission. Future reservation
// phases may change logical counts, never offsets/capacities/widths. Growth is
// an explicit host copy/reinitialize boundary preserving accepted logical IDs.
public SolverStatus pps_admit_layout()
{
    if (!pps_identity_is_valid()) return ts_invalid(66u, TS_INVALID, TS_INVALID);
    for (uint table = 0u; table < PPS_TABLES; table++)
    {
        uint4 span; uint accepted;
        if (!pps_descriptor(table, span, accepted)) return ts_invalid(66u, table, TS_INVALID);
        if (span.z == 0u) continue;
        uint end = span.x + span.z * pps_width(table);
        for (uint other = 0u; other < table; other++)
        {
            uint4 prior; uint unused;
            if (!pps_descriptor(other, prior, unused)) return ts_invalid(66u, table, other);
            if (prior.z != 0u && span.x < prior.x + prior.z * pps_width(other) && prior.x < end)
                return ts_invalid(66u, table, other);
        }
    }
    return ts_ok();
}
public bool pps_count(uint table, out uint count)
{
    count = 0u;
    if (!((table < PPS_TABLES) & pps_physical_header())) return false;
    uint directory = PPS_DIRECTORY + table * 6u;
    uint admitted = trait_solver_proof_store[directory + 3u];
    uint logical = trait_solver_proof_store[directory + 1u];
    if (!((logical != TS_INVALID) & (admitted <= logical))) return false;
    count = admitted; return true;
}
public bool pps_span(uint table, uint first, uint count)
{
    uint rows;
    bool known = pps_count(table, rows);
    return known & (first <= rows) & (count <= rows - first);
}
// Safe projection after layout admission. For readers, the admitted count is
// authority. Writers may address reserved rows only after a disjoint GPU count
// and prefix reservation; acceptance never follows from this writer bound.
public bool pps_address(uint table, uint row, uint field, uint fields, bool write,
    out uint address)
{
    address = TS_INVALID;
    // The directory guard makes the six fixed directory reads safe.
    if (!((table < PPS_TABLES) & pps_physical_header())) return false;
    uint width = pps_width(table);
    uint directory = PPS_DIRECTORY + table * 6u;
    uint offset = trait_solver_proof_store[directory];
    uint logical = trait_solver_proof_store[directory + 1u];
    uint capacity = trait_solver_proof_store[directory + 2u];
    uint admitted = trait_solver_proof_store[directory + 3u];
    uint accepted = trait_solver_proof_store[directory + 4u];
    uint words = proof_store_params.word_count;
    if (!((fields != 0u) & (field < width) & (fields <= width - field) &
        (logical != TS_INVALID) & (logical <= capacity) & (admitted <= logical) &
        (accepted <= admitted) & (row < select(write, logical, admitted)) &
        !(write & (table < PPS_PERSISTENT_TABLES) & (row < admitted)) &
        (offset <= words) & (row < ts_rows_in(offset, words, width)))) return false;
    address = offset + row * width + field;
    return true;
}
public bool pps_read2(uint table, uint row, uint field, out uint2 value)
{
    value = uint2(TS_INVALID, TS_INVALID); uint address;
    if (!pps_address(table, row, field, 2u, false, address)) return false;
    value = uint2(trait_solver_proof_store[address], trait_solver_proof_store[address + 1u]);
    return true;
}
public bool pps_read4(uint table, uint row, uint field, out uint4 value)
{
    value = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID); uint address;
    if (!pps_address(table, row, field, 4u, false, address)) return false;
    value = uint4(trait_solver_proof_store[address], trait_solver_proof_store[address + 1u],
        trait_solver_proof_store[address + 2u], trait_solver_proof_store[address + 3u]);
    return true;
}
public bool pps_read8(uint table, uint row, out uint4 low, out uint4 high)
{
    low = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID); high = low;
    uint address;
    if (!pps_address(table, row, 0u, 8u, false, address)) return false;
    low = uint4(trait_solver_proof_store[address], trait_solver_proof_store[address + 1u],
        trait_solver_proof_store[address + 2u], trait_solver_proof_store[address + 3u]);
    high = uint4(trait_solver_proof_store[address + 4u], trait_solver_proof_store[address + 5u],
        trait_solver_proof_store[address + 6u], trait_solver_proof_store[address + 7u]);
    return true;
}
// A validator may inspect its own fully emitted pending row before advancing
// the admitted prefix. This never permits that row to support another proof.
public bool pps_read_pending2(uint table, uint row, uint field, out uint2 value)
{
    value = uint2(TS_INVALID, TS_INVALID); uint address;
    if (!pps_address(table, row, field, 2u, true, address)) return false;
    value = uint2(trait_solver_proof_store[address], trait_solver_proof_store[address + 1u]);
    return true;
}
public bool pps_read_pending4(uint table, uint row, uint field, out uint4 value)
{
    value = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID); uint address;
    if (!pps_address(table, row, field, 4u, true, address)) return false;
    value = uint4(trait_solver_proof_store[address], trait_solver_proof_store[address + 1u],
        trait_solver_proof_store[address + 2u], trait_solver_proof_store[address + 3u]);
    return true;
}
public bool pps_read_pending8(uint table, uint row, out uint4 low, out uint4 high)
{
    low = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID); high = low;
    uint address;
    if (!pps_address(table, row, 0u, 8u, true, address)) return false;
    low = uint4(trait_solver_proof_store[address], trait_solver_proof_store[address + 1u],
        trait_solver_proof_store[address + 2u], trait_solver_proof_store[address + 3u]);
    high = uint4(trait_solver_proof_store[address + 4u], trait_solver_proof_store[address + 5u],
        trait_solver_proof_store[address + 6u], trait_solver_proof_store[address + 7u]);
    return true;
}
public bool pps_write2(uint table, uint row, uint field, uint2 value)
{
    uint address;
    if (!pps_address(table, row, field, 2u, true, address)) return false;
    trait_solver_proof_store[address] = value.x;
    trait_solver_proof_store[address + 1u] = value.y;
    return true;
}
public bool pps_write8(uint table, uint row, uint4 low, uint4 high)
{
    uint address;
    if (!pps_address(table, row, 0u, 8u, true, address)) return false;
    trait_solver_proof_store[address] = low.x;
    trait_solver_proof_store[address + 1u] = low.y;
    trait_solver_proof_store[address + 2u] = low.z;
    trait_solver_proof_store[address + 3u] = low.w;
    trait_solver_proof_store[address + 4u] = high.x;
    trait_solver_proof_store[address + 5u] = high.y;
    trait_solver_proof_store[address + 6u] = high.z;
    trait_solver_proof_store[address + 7u] = high.w;
    return true;
}
