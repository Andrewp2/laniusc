// Debug validation, step 2 of 3: chain every interned row into the bucket of
// its coarse key (canonical_crosscheck.slang), and record the smallest row of
// each record (its representative in 90_validate). 88_validate_table cleared
// the heads and the owners.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_crosscheck;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint buckets = crosscheck_buckets();
    if (row >= crosscheck_rows() || buckets == 0u || !crosscheck_row(row)) return;
    uint id = canonical_row[row];
    if (id >= CT_FIRST_RECORD && id < crosscheck_owner_capacity())
        InterlockedMin(canonical_crosscheck_owner[id], row);
    // Push onto the bucket's chain with CAS: Slang 2026.2 mislowers
    // InterlockedExchange's original-value operand. The links are read by
    // the next dispatch, so the link may be written before the push.
    uint bucket = coarse_hash(row) % buckets;
    uint head = canonical_crosscheck_links[bucket];
    for (;;)
    {
        canonical_crosscheck_links[buckets + row] = head;
        uint seen;
        InterlockedCompareExchange(canonical_crosscheck_links[bucket], head, row + 1u, seen);
        if (seen == head) break;
        head = seen;
    }
}
