// Projection step 6: one lane per lowering batch. Batch b holds the ranks
// whose first global row is in [b * C, (b + 1) * C) for the configured C,
// so a rank never straddles two batches and a batch exceeds C rows by less
// than one instance. pj_batches[b]: (lo, hi, rows with the root row,
// tokens), side lengths 0..3, (side lengths 4..6, decoded string words). The status receives
// the largest batch, for the host's one allocation of the batch columns.
import type_checker.retention.projection.retained_projection_workspace;

RWStructuredBuffer<uint4> pj_batches;

// The first rank whose first row is at least `g` (the instance count when
// none is).
uint first_rank_at(uint g)
{
    uint lo = 0u;
    uint hi = pj_instance_count();
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (pj_base_at(mid, PJ_C_ROWS) < g) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

uint span(uint lo, uint hi, uint column) { return pj_base_at(hi, column) - pj_base_at(lo, column); }

public void plan_retained_lowering_batches(uint b)
{
    uint rows = pj_total(PJ_C_ROWS);
    uint c = max(pj_config[PJ_CFG_BATCH_ROWS], 1u);
    uint batches = (rows + c - 1u) / c;
    if (b == 0u) pj_status[PJ_S_BATCHES] = batches;
    uint capacity; uint s;
    pj_batches.GetDimensions(capacity, s);
    if (b >= batches || (b + 1u) * PJ_BATCH_WORDS > capacity) return;
    uint lo = first_rank_at(b * c);
    uint hi = first_rank_at((b + 1u) * c);
    uint4 w0 = uint4(lo, hi, 0u, 0u);
    uint4 w1 = uint4(0u, 0u, 0u, 0u);
    uint4 w2 = uint4(0u, 0u, 0u, 0u);
    if (lo < hi)
    {
        w0.z = 1u + span(lo, hi, PJ_C_ROWS);
        w0.w = span(lo, hi, PJ_C_TOKENS);
        w1 = uint4(span(lo, hi, PJ_C_SIDE + 0u), span(lo, hi, PJ_C_SIDE + 1u),
            span(lo, hi, PJ_C_SIDE + 2u), span(lo, hi, PJ_C_SIDE + 3u));
        w2 = uint4(span(lo, hi, PJ_C_SIDE + 4u), span(lo, hi, PJ_C_SIDE + 5u),
            span(lo, hi, PJ_C_SIDE + 6u),
            pj_string_offsets[pj_base_at(hi,PJ_C_ROWS)] - pj_string_offsets[pj_base_at(lo,PJ_C_ROWS)]);
        InterlockedMax(pj_status[PJ_S_BATCH_STRING_WORDS],w2.w);
        InterlockedMax(pj_status[PJ_S_BATCH_ROWS], w0.z);
        InterlockedMax(pj_status[PJ_S_BATCH_TOKENS], w0.w + 1u);
        InterlockedMax(pj_status[PJ_S_BATCH_SIDE],
            max(max(max(w1.x, w1.y), max(w1.z, w1.w)), max(max(w2.x, w2.y), w2.z)));
        InterlockedAdd(pj_status[PJ_S_BATCH_NONEMPTY], 1u);
    }
    pj_batches[b * PJ_BATCH_WORDS + 0u] = w0;
    pj_batches[b * PJ_BATCH_WORDS + 1u] = w1;
    pj_batches[b * PJ_BATCH_WORDS + 2u] = w2;
}
