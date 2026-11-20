// One substitution request per schema record of the round's terms.
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
public RWStructuredBuffer<uint4> sb_requests;
public void emit_retained_schema_requests(uint q)
{
    if (q >= ps_round_count()) return;
    uint lo = 0u; uint hi = ps_round_terms();
    while (lo+1u < hi)
    {
        uint mid = lo+(hi-lo)/2u;
        if (ps_scan(mid) <= q) lo = mid; else hi = mid;
    }
    uint term = ps_round_lo()+lo;
    uint entry = ps_entry(term);
    uint4 d2 = rt_dir[entry*RT_DIR_WORDS+2u];
    uint ordinal = q-ps_scan(lo);
    uint4 field = rt_schema[d2.y+ordinal];
    uint kind = field.y & 0xffu;
    uint value = kind == RT_SCHEMA_FIELD || kind == RT_SCHEMA_PAYLOAD ? field.w : 1u;
    sb_requests[q] = uint4(rt_term_words(term).x,term,value,q);
    if (ordinal == 0u) pj_schema_ranges[term] = uint2(ps_round_base()+q,d2.z);
}
