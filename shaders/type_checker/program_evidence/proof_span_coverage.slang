// Pending allocation metadata has no authority by itself. Admission must prove
// that checked owner spans cover a destination suffix exactly once.
import type_checker.program_evidence.abi;

public interface IProofSpanSource
{
    static bool span(uint owner, uint table, out uint first, out uint count);
}
public static const uint PPS_COVER_TILE_ROWS = 1024u;
public static const uint PPS_COVER_TILE_WORDS = 32u;

bool pps_cover_charge(inout uint visits)
{
    if (visits >= PEV_VISIT_LIMIT) return false;
    visits++; return true;
}

// O(S * max(1, ceil(N/1024)) + N/32) for a valid cover, fixed 32-word
// scratch. The caller shares the visit budget across all destination tables.
// Every owner-span query, bitmap update and final coverage check is charged. Resource exhaustion
// is a failure before publication, even if the spans would form a valid cover.
public EvidenceStatus pps_check_span_cover<Source : IProofSpanSource>(uint table,
    uint first, uint end, uint owner_first, uint owner_end, inout uint visits)
{
    if (first > end || owner_first > owner_end || end == PEV_INVALID || owner_end == PEV_INVALID)
        return pev_invalid(66u, table, first);
    uint tile_first = first;
    [loop]
    do
    {
        uint tile_rows = min(end - tile_first, PPS_COVER_TILE_ROWS);
        uint tile_end = tile_first + tile_rows;
        uint words = (tile_rows + 31u) / 32u;
        uint covered[PPS_COVER_TILE_WORDS];
        for (uint word = 0u; word < words; word++) covered[word] = 0u;
        [loop]
        for (uint owner = owner_first; owner < owner_end; owner++)
        {
            if (!pps_cover_charge(visits))
                return pev_limit(7u, table, PEV_VISIT_LIMIT + 1u, PEV_VISIT_LIMIT);
            uint span_first; uint span_count;
            if (!Source.span(owner, table, span_first, span_count) ||
                (span_count == 0u ? span_first != 0u :
                    (span_first < first || span_first >= end || span_count > end - span_first)))
                return pev_invalid(66u, table, owner);
            if (span_count == 0u) continue;
            uint begin = max(span_first, tile_first);
            uint finish = min(span_first + span_count, tile_end);
            if (begin >= finish) continue;
            uint local_begin = begin - tile_first; uint local_end = finish - tile_first;
            [loop]
            for (uint word = local_begin / 32u; word <= (local_end - 1u) / 32u; word++)
            {
                if (!pps_cover_charge(visits))
                    return pev_limit(7u, table, PEV_VISIT_LIMIT + 1u, PEV_VISIT_LIMIT);
                uint base = word * 32u;
                uint low = max(local_begin, base) - base;
                uint high = min(local_end - base, 32u);
                uint mask = (high == 32u ? 0xffffffffu : (1u << high) - 1u) & (0xffffffffu << low);
                if ((covered[word] & mask) != 0u) return pev_invalid(66u, table, owner);
                covered[word] |= mask;
            }
        }
        for (uint word = 0u; word < words; word++)
        {
            if (!pps_cover_charge(visits))
                return pev_limit(7u, table, PEV_VISIT_LIMIT + 1u, PEV_VISIT_LIMIT);
            uint bits = min(tile_rows - word * 32u, 32u);
            uint expected = bits == 32u ? 0xffffffffu : (1u << bits) - 1u;
            if (covered[word] != expected) return pev_invalid(66u, table, tile_first + word * 32u);
        }
        tile_first = tile_end;
    } while (tile_first < end);
    return pev_ok();
}

// The serial audit's charges in closed form, for the grid-wide commit audits
// (proof_commit_audit.slang). They prove success only: a commit whose audit
// lanes found an exact cover publishes when these charges stay within
// PEV_VISIT_LIMIT, and otherwise runs the serial audit for its exact result.

// min(total + count, PEV_VISIT_LIMIT + 1).
public uint pps_cover_charge_add(uint total, uint count)
{
    uint over = PEV_VISIT_LIMIT + 1u;
    return (total >= over || count >= over - total) ? over : total + count;
}
// min(a * b, PEV_VISIT_LIMIT + 1) without 64-bit arithmetic. Factors at most
// 0xffff multiply exactly; otherwise either factor is at most one, or the
// product is at least 2 * 0x10000, past the limit while it stays below 2^17.
uint pps_cover_charge_product(uint a, uint b)
{
    uint over = PEV_VISIT_LIMIT + 1u;
    if (PEV_VISIT_LIMIT >= 0x1ffffu) return over;
    if ((a <= 0xffffu && b <= 0xffffu) || a <= 1u || b <= 1u) return min(a * b, over);
    return over;
}
// Serial charges per tile: one per owner and one per bitmap word.
uint pps_cover_tiles(uint rows)
{ return rows == 0u ? 1u : rows / PPS_COVER_TILE_ROWS + (rows % PPS_COVER_TILE_ROWS != 0u ? 1u : 0u); }
uint pps_cover_words(uint rows)
{ return rows / 32u + (rows % 32u != 0u ? 1u : 0u); }
// Bitmap words one owner's span is charged for. Serial tiles start at
// multiples of 32 rows from `first`, so across all tiles these are the words
// the span touches, counted from `first`.
public uint pps_cover_span_words(uint first, uint span_first, uint span_count)
{
    uint offset = span_first - first;
    return ((offset + span_count - 1u) >> 5u) - (offset >> 5u) + 1u;
}
// Adds what pps_check_span_cover charges for one exact cover of `rows` rows by
// `owners` owners, less the owners' bitmap words.
public uint pps_cover_charge(uint charges, uint rows, uint owners)
{
    charges = pps_cover_charge_add(charges, pps_cover_charge_product(pps_cover_tiles(rows), owners));
    return pps_cover_charge_add(charges, pps_cover_words(rows));
}
