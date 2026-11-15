import type_checker.retention.projection.schema.common;
RWStructuredBuffer<uint4> sb_requests;
RWStructuredBuffer<uint> sb_request_count;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint q = ps_lane(id);
    if (q == 0u) sb_request_count[0] = ps_status[0];
    if (q >= ps_status[0] || ps_status[2] != 0u) return;
    uint lo = 0u; uint hi = ps_config[1]-ps_config[0];
    while (lo+1u < hi)
    {
        uint mid = lo+(hi-lo)/2u;
        if (ps_scan(mid) <= q) lo = mid; else hi = mid;
    }
    uint term = ps_config[0]+lo;
    uint entry = ps_entry(term);
    uint4 d2 = rt_dir[entry*RT_DIR_WORDS+2u];
    uint ordinal = q-ps_scan(lo);
    uint4 field = rt_schema[d2.y+ordinal];
    uint kind = field.y & 0xffu;
    uint value = kind == RT_SCHEMA_FIELD || kind == RT_SCHEMA_PAYLOAD ? field.w : 1u;
    sb_requests[q] = uint4(rt_term_words(term).x,term,value,q);
    if (ordinal == 0u) pj_schema_ranges[term] = uint2(ps_config[2]+q,d2.z);
}
