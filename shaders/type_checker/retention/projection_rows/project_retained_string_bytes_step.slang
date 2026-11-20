// One lane per output word, including decoded zero and padding bytes.
// The exclusive offsets locate the owning literal with a binary search;
// no lane walks the bytes of a long string.
import type_checker.retention.projection.retained_lowering_columns;

public void project_retained_string_bytes(Batch b, uint word)
{
    uint start = pj_base_at(b.lo,PJ_C_ROWS);
    uint end = pj_base_at(b.hi,PJ_C_ROWS);
    uint base = pj_string_offsets[start];
    uint words = pj_string_offsets[end] - base;
    // A batch recorded before the check was read back may exceed the
    // column; publish_retained_lowering_batch's gate then discards it.
    uint capacity; uint stride;
    ob_string_data.GetDimensions(capacity, stride);
    if (word >= words || word >= capacity) return;
    uint absolute = base + word;
    uint lo = start;
    uint hi = end;
    while (lo < hi)
    {
        uint mid = lo + (hi-lo)/2u;
        if (pj_string_offsets[mid+1u] <= absolute) lo = mid+1u; else hi = mid;
    }
    uint rank = pj_rank_of(PJ_C_ROWS,lo,b.lo,b.hi);
    uint row = lo - pj_base_at(rank,PJ_C_ROWS);
    uint string = pj_row(rank,row,2u).y;
    uint source = pj_side(rank,PJ_SIDE_STRINGS,string,0u).y;
    ob_string_data[word] = rt_seg_bytes[source + absolute - pj_string_offsets[lo]];
}
