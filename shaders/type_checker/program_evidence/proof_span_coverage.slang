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

// The same audit by one 256-lane workgroup (the commit stages that run as a
// single group). Every lane calls it in uniform control flow: its inputs are
// uniform, and it combines the lanes' results in groupshared memory behind
// barriers. It proves success only. True means that pps_check_span_cover over
// the same inputs returns ok, and that it charges exactly the visits added
// to `charges`, which saturates at PEV_VISIT_LIMIT + 1. So the serial audit
// succeeds when the caller's whole charge stays within PEV_VISIT_LIMIT.
// False proves nothing; the caller then runs the serial audit for its exact
// failure.
public static const uint PPS_GROUP_LANES = 256u;
static const uint PPS_GROUP_COVER_WORDS = 3072u; // 12 KiB: 98,304 rows per pass
groupshared uint pps_group_cover_bits[PPS_GROUP_COVER_WORDS];
groupshared uint pps_group_cover_failed;
groupshared uint pps_group_cover_touched;

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

public bool pps_group_check_span_cover<Source : IProofSpanSource>(uint lane, uint table,
    uint first, uint end, uint owner_first, uint owner_end, inout uint charges)
{
    if (first > end || owner_first > owner_end || end == PEV_INVALID || owner_end == PEV_INVALID)
        return false;
    uint owners = owner_end - owner_first;
    if (lane == 0u) { pps_group_cover_failed = 0u; pps_group_cover_touched = 0u; }
    bool failed = false;
    // Serial word charges of this lane's owners. Serial tiles start at
    // multiples of 32 rows from `first`, so an owner's charged words across
    // all tiles are the words its span touches, counted from `first`.
    uint touched = 0u;
    uint tile_first = first;
    [loop]
    do
    {
        uint tile_rows = min(end - tile_first, PPS_GROUP_COVER_WORDS * 32u);
        uint tile_end = tile_first + tile_rows;
        uint words = (tile_rows + 31u) / 32u;
        for (uint word = lane; word < words; word += PPS_GROUP_LANES) pps_group_cover_bits[word] = 0u;
        GroupMemoryBarrierWithGroupSync();
        [loop]
        for (uint index = lane; index < owners; index += PPS_GROUP_LANES)
        {
            uint span_first; uint span_count;
            if (!Source.span(owner_first + index, table, span_first, span_count) ||
                (span_count == 0u ? span_first != 0u :
                    (span_first < first || span_first >= end || span_count > end - span_first)))
            { failed = true; continue; }
            if (span_count == 0u) continue;
            uint offset = span_first - first;
            if (tile_first == first)
                touched = pps_cover_charge_add(touched,
                    ((offset + span_count - 1u) >> 5u) - (offset >> 5u) + 1u);
            uint begin = max(span_first, tile_first);
            uint finish = min(span_first + span_count, tile_end);
            if (begin >= finish) continue;
            uint local_begin = begin - tile_first; uint local_end = finish - tile_first;
            [loop]
            for (uint word = local_begin / 32u; word <= (local_end - 1u) / 32u; word++)
            {
                uint base = word * 32u;
                uint low = max(local_begin, base) - base;
                uint high = min(local_end - base, 32u);
                uint mask = (high == 32u ? 0xffffffffu : (1u << high) - 1u) & (0xffffffffu << low);
                uint previous;
                InterlockedOr(pps_group_cover_bits[word], mask, previous);
                if ((previous & mask) != 0u) failed = true;
            }
        }
        GroupMemoryBarrierWithGroupSync();
        for (uint word = lane; word < words; word += PPS_GROUP_LANES)
        {
            uint bits = min(tile_rows - word * 32u, 32u);
            uint expected = bits == 32u ? 0xffffffffu : (1u << bits) - 1u;
            if (pps_group_cover_bits[word] != expected) failed = true;
        }
        if (failed) InterlockedOr(pps_group_cover_failed, 1u);
        GroupMemoryBarrierWithGroupSync();
        tile_first = tile_end;
    } while (tile_first < end && pps_group_cover_failed == 0u);
    // Each lane adds at most PEV_VISIT_LIMIT + 1, so the sum cannot wrap.
    InterlockedAdd(pps_group_cover_touched, touched);
    GroupMemoryBarrierWithGroupSync();
    bool covered = pps_group_cover_failed == 0u;
    uint touched_total = pps_group_cover_touched;
    // The next audit resets the shared words only after every lane read them.
    GroupMemoryBarrierWithGroupSync();
    if (!covered) return false;
    uint rows = end - first;
    charges = pps_cover_charge_add(charges, pps_cover_charge_product(pps_cover_tiles(rows), owners));
    charges = pps_cover_charge_add(charges, touched_total);
    charges = pps_cover_charge_add(charges, pps_cover_words(rows));
    return true;
}
