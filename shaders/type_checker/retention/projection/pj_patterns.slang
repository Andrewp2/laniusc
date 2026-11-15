__exported import type_checker.retention.projection.pj_schema;
__exported import type_checker.retention.projection.pj_common;

// Variant syntax carries either a local definition or the imported ordinal
// artifact. Imported patterns also retain their checked nominal type.
public uint pj_pattern_variant(uint rank, uint row)
{
    uint4 binding = pj_row(rank,row,5u);
    uint4 value = pj_row(rank,row,6u);
    if (binding.x == RT_BIND_VARIANT) return binding.z;
    return value.y == RT_CONST_VARIANT ? value.z : RT_INVALID;
}

public uint4 pj_variant_schema(uint type, uint variant)
{
    if (!rt_is_stored_term(type) || rt_term_kind(type) != RT_KIND_NAMED)
        return uint4(RT_INVALID,0u,0u,0u);
    uint decl = rt_term_words(type).x;
    uint entry = pj_dir_entry(decl);
    if (entry == RT_INVALID || rt_dir[entry*RT_DIR_WORDS].y != 6u)
        return uint4(RT_INVALID,0u,0u,0u);
    uint4 d1 = rt_dir[entry*RT_DIR_WORDS+1u];
    uint4 d2 = rt_dir[entry*RT_DIR_WORDS+2u];
    if (variant >= d1.w || variant >= d2.z) return uint4(RT_INVALID,0u,0u,0u);
    uint4 record = rt_schema[d2.y+variant];
    if (record.x != decl || record.y != (RT_SCHEMA_VARIANT | (variant << 8u)) ||
        record.w > d2.z || record.z > d2.z-record.w) return uint4(RT_INVALID,0u,0u,0u);
    return record;
}
