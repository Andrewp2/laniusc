// Lane i > 0 counts the schema records of term lo + i - 1; lane 0 is the
// scan's leading zero. The round's term-lane dispatch sizes this pass.
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
public void count_retained_schema_requests(uint lane)
{
    uint n = ps_round_terms();
    if (lane > n) return;
    uint entry = lane == 0u ? RT_INVALID : ps_entry(ps_round_lo()+lane-1u);
    uint value = entry == RT_INVALID ? 0u : rt_dir[entry*RT_DIR_WORDS+2u].z;
    // One term's records fit far below this; a larger count is corrupt and
    // would let the block sums wrap.
    if (value > 0xffffffu) { InterlockedOr(ps_status[PS_ERROR],2u); value = 0u; }
    ps_scan_a[lane] = value;
}
