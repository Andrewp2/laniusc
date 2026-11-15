__exported import type_checker.retention.retention_store;
public StructuredBuffer<uint> ps_config;
public RWStructuredBuffer<uint> ps_scan_a;
public RWStructuredBuffer<uint> ps_scan_b;
public globallycoherent RWStructuredBuffer<uint> ps_status;
public RWStructuredBuffer<uint2> pj_schema_ranges;
public RWStructuredBuffer<uint2> pj_schema_fields;
// config: term lo, term hi, output base, scan distance, scan input, run,
// generation. status: requests, term hi after substitution, overflow.
public uint ps_lane(uint3 id) { return id.x + id.y * 16776960u; }
public uint ps_scan(uint i) { return ps_config[4] == 0u ? ps_scan_a[i] : ps_scan_b[i]; }
public uint ps_entry(uint term)
{
    if (term < RT_FIRST_TERM || term >= rt_counts[RT_A_TERMS] ||
        rt_term_kind(term) != RT_KIND_NAMED || !rt_term_closed(term)) return RT_INVALID;
    uint decl = rt_term_words(term).x;
    if (decl == 0u || decl >= rt_counts[RT_A_DECLS]) return RT_INVALID;
    uint def = rt_decl_def[decl];
    if (def == 0u || def > rt_counts[RT_A_DIR]) return RT_INVALID;
    uint4 d0 = rt_dir[(def-1u)*RT_DIR_WORDS];
    uint4 d3 = rt_dir[(def-1u)*RT_DIR_WORDS+3u];
    return d0.x == decl && (d0.y == 5u || d0.y == 6u) &&
        d0.w == RT_DIR_COMMITTED && d3.w == 0u ? def-1u : RT_INVALID;
}
