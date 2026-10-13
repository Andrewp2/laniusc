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
