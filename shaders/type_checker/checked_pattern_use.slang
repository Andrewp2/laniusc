import hir_records;

// Compact match arms retain source order. A path in a pattern identifies a
// variant; it does not request construction of a value with inferred operands.
public bool checked_token_in_match_pattern(uint token, uint hir_count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<uint> arm_count,
    StructuredBuffer<HirMatchArm> arms)
{
    uint low = 0u; uint high = min(arm_count[0u], hir_count);
    while (low < high)
    {
        uint middle = low + (high - low) / 2u;
        uint pattern = arms[middle].pattern;
        if (pattern < hir_count && cores[pattern].token_start <= token) low = middle + 1u;
        else high = middle;
    }
    if (low == 0u) return false;
    uint pattern = arms[low - 1u].pattern;
    return pattern < hir_count && cores[pattern].token_start <= token &&
        token <= cores[pattern].token_end;
}
