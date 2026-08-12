// Direct lookup from an exact canonical path-prefix id to the lowest module row.
//
// Canonical ids are slots in the path-prefix interner's two-times-load table.
// The table stores inverted module ids so zero remains the empty value and an
// atomic maximum deterministically selects the lowest row for duplicate paths.

static const uint MODULE_LOOKUP_INVALID = 0xffffffffu;

uint module_lookup_capacity(uint path_segment_capacity)
{
    return path_segment_capacity * 2u;
}

uint module_lookup_encode(uint module_id)
{
    return MODULE_LOOKUP_INVALID - module_id;
}

uint module_lookup_decode(uint encoded)
{
    return encoded == 0u ? MODULE_LOOKUP_INVALID : MODULE_LOOKUP_INVALID - encoded;
}

void module_lookup_insert_lowest(
    uint canonical_id,
    uint module_id,
    uint path_segment_capacity,
    RWStructuredBuffer<uint> module_by_canonical_id)
{
    if (canonical_id >= module_lookup_capacity(path_segment_capacity))
        return;
    uint ignored;
    InterlockedMax(
        module_by_canonical_id[canonical_id],
        module_lookup_encode(module_id),
        ignored);
}

uint module_lookup_find(
    uint canonical_id,
    uint path_segment_capacity,
    StructuredBuffer<uint> module_by_canonical_id)
{
    return canonical_id < module_lookup_capacity(path_segment_capacity)
        ? module_lookup_decode(module_by_canonical_id[canonical_id])
        : MODULE_LOOKUP_INVALID;
}
