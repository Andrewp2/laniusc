import type_checker.retention.projection.pj_common;
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

// Struct `t`'s field of declaration ordinal `ordinal`: its closed type,
// native word offset and words.
public uint3 pj_struct_field(uint t, uint ordinal)
{
    uint decl = rt_term_words(t).x;
    uint entry = pj_dir_entry(decl);
    if (entry == RT_INVALID) return uint3(RT_INVALID, RT_INVALID, RT_INVALID);
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint offset = 0u;
    uint3 found = uint3(RT_INVALID, RT_INVALID, RT_INVALID);
    for (uint k = 0u; k < d2.z; k++)
    {
        uint4 record = rt_schema[d2.y + k];
        if ((record.y & 0xffu) != RT_SCHEMA_FIELD) continue;
        uint field = pj_schema_type(t,k);
        uint words = pj_words(field);
        uint o = record.y >> 8u;
        if (o == ordinal) found = uint3(field, 0u, words);
        else if (o < ordinal) offset += words;
    }
    if (found.x != RT_INVALID) found.y = offset;
    return found;
}
