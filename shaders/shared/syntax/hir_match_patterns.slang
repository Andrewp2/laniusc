import hir_records;

// Compact match arms are contiguous per match: the arms of a match are rows
// payload.b .. payload.b + payload.c, in source order within that match. The
// table as a whole is not in source order, because a match nested in an
// earlier arm owns its own range. So a node is placed in a pattern through its
// enclosing match, not by a search over the whole arm table.

// Pattern syntax is names, literals, paths, and the types and constant
// arguments a path segment can carry. Every other node lies outside every
// pattern, so the climb below stops at the first one.
[ForceInline]
bool hir_pattern_syntax_kind(uint kind)
{
    return kind == 5u || kind == 17u || kind == 22u || kind == 23u || kind == 33u;
}

// The match reached by climbing from the node through pattern syntax only, or
// INVALID.
uint hir_pattern_climb_match(uint node, uint hir_count, StructuredBuffer<HirCore> cores)
{
    uint current = node;
    // The parent forest is acyclic, so the bound is only a guard.
    for (uint depth = 0u; depth < hir_count; depth++)
    {
        if (!hir_pattern_syntax_kind(cores[current].kind)) return 0xffffffffu;
        uint parent = cores[current].parent;
        if (parent >= hir_count || parent == current) return 0xffffffffu;
        if (cores[parent].kind == 34u) return parent;
        current = parent;
    }
    return 0xffffffffu;
}

// Whether one of the match's arm patterns contains the span. Within a match
// the arms are in source order, so the last pattern starting at or before the
// span is the only candidate.
bool hir_match_arm_pattern_contains(uint match, HirCore candidate, uint hir_count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> arm_count, StructuredBuffer<HirMatchArm> arms)
{
    HirPayload value = payloads[match];
    uint total = min(arm_count[0u], hir_count);
    if (value.b > total || value.c > total - value.b) return false;
    uint low = value.b;
    uint high = value.b + value.c;
    while (low < high)
    {
        uint middle = low + (high - low) / 2u;
        uint pattern = arms[middle].pattern;
        if (pattern < hir_count && cores[pattern].token_start <= candidate.token_start)
            low = middle + 1u;
        else
            high = middle;
    }
    if (low == value.b) return false;
    uint pattern = arms[low - 1u].pattern;
    if (pattern >= hir_count) return false;
    // The pattern node spans its path; nested payload patterns follow it.
    // The arm's pattern syntax ends where its result begins.
    uint result = arms[low - 1u].result;
    uint end = result < hir_count ? cores[result].token_start : cores[pattern].token_end;
    return candidate.token_start >= cores[pattern].token_start &&
        candidate.token_end <= end;
}

// Whether the node lies inside an arm pattern of a match, as opposed to its
// scrutinee or an arm result. A path in a pattern names a variant; it does
// not construct a value.
public bool hir_node_in_match_pattern(uint node, uint hir_count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> arm_count, StructuredBuffer<HirMatchArm> arms)
{
    if (node >= hir_count) return false;
    uint match = hir_pattern_climb_match(node, hir_count, cores);
    return match < hir_count &&
        hir_match_arm_pattern_contains(match, cores[node], hir_count, cores, payloads, arm_count, arms);
}
