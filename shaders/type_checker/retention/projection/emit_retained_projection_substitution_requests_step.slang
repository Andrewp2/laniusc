// Projection step 2: one lane per substitution request. Each rank asks for
// its signature result and parameters, every body row's term and every
// use's environment and result, all under (DeclId, ENV). A symbolic constant
// row requests its value: the result includes its declared scalar type.
// A row or use
// without a resolved term asks for the unit scalar, whose result nothing
// reads. The tag is the request index. Requests past the buffer are not
// written; the count tells the engine how many the producer needed.
import type_checker.retention.projection.retained_projection_workspace;

public RWStructuredBuffer<uint4> sb_requests;
public RWStructuredBuffer<uint> sb_request_count;

uint resolved_or_unit(uint term) { return rt_is_resolved(term) ? term : SCALAR_UNIT; }

public void emit_retained_projection_substitution_request(uint q)
{
    uint n = pj_instance_count();
    uint total = pj_base[n * PJ_COLUMNS + PJ_C_REQUESTS];
    if (q == 0u) sb_request_count[0u] = total;
    if (q >= total) return;
    uint capacity; uint s;
    sb_requests.GetDimensions(capacity, s);
    if (q >= capacity) return;
    uint rank = pj_rank_of(PJ_C_REQUESTS, q, 0u, n);
    uint o = q - pj_base_at(rank, PJ_C_REQUESTS);
    uint4 i0 = pj_inf(rank, 0u);
    uint4 i1 = pj_inf(rank, 1u);
    uint sig = pj_inf(rank, 3u).w;
    uint term;
    if (o <= i1.z) term = rt_sigs[sig + o];
    else if (o < 1u + i1.z + i1.x)
    {
        uint row = o - 1u - i1.z;
        uint4 value = pj_row(rank, row, 6u);
        term = value.y == RT_CONST_SYMBOLIC && pj_row(rank, row, 0u).x != RT_HIR_TYPE
            ? value.z : resolved_or_unit(pj_row(rank, row, 3u).x);
    }
    else
    {
        uint use_offset = o - 1u - i1.z - i1.x;
        uint word = use_offset / i1.w;
        uint use = use_offset % i1.w;
        term = resolved_or_unit(pj_use(rank,use,1u)[word]);
    }
    sb_requests[q] = uint4(i0.x, i0.y, term, q);
}
