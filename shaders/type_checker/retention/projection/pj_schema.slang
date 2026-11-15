import type_checker.retention.retention_store;
public StructuredBuffer<uint2> pj_schema_ranges;
public StructuredBuffer<uint2> pj_schema_fields;
// `ordinal` is the entry's schema-block index, not a source field ordinal.
public uint pj_schema_type(uint term, uint ordinal)
{
    uint n; uint stride; pj_schema_ranges.GetDimensions(n,stride);
    if (term >= n) return RT_INVALID;
    uint2 range = pj_schema_ranges[term];
    if (ordinal >= range.y) return RT_INVALID;
    uint2 result = pj_schema_fields[range.x+ordinal];
    return result.y == 0u ? result.x : RT_INVALID;
}
