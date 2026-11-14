// Shared by steps 12b and 12c: the retained body a job token belongs to.
// The job's segments are scan-placed in HIR row order, which is source
// order, so their first tokens (rt_x_seg_token) ascend.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.source_tables;

public struct TokenBody
{
    public uint segment;    // store segment index, RT_INVALID when none
    public uint first;      // the body's first job token
    public uint count;      // its tokens
    public uint text_start; // job source byte of its text
    public uint text_end;
}

public TokenBody token_body(uint token)
{
    TokenBody b;
    b.segment = RT_INVALID; b.first = 0u; b.count = 0u; b.text_start = 0u; b.text_end = 0u;
    uint segments = scan_at(0xffffffffu).w;
    uint seg_base = rt_x_counts[RT_X_BASE + RT_A_SEGMENTS];
    if (segments == 0u || seg_base == RT_INVALID) return b;
    uint lo = 0u; uint hi = segments;
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (rt_x_seg_token[mid] <= token) lo = mid + 1u;
        else hi = mid;
    }
    if (lo == 0u) return b;
    uint segment = seg_base + lo - 1u;
    uint first = rt_x_seg_token[lo - 1u];
    uint count = rt_segments[segment * RT_SEG_WORDS + 2u].w;
    if (token - first >= count) return b;
    b.segment = segment;
    b.first = first;
    b.count = count;
    uint2 text = body_text_range(first, count);
    b.text_start = text.x;
    b.text_end = text.y;
    return b;
}

// The job source bytes [start, end) token `token` of body `b` owns: its own
// bytes and the bytes up to the next token of the body (or the body's end),
// so the tokens partition the body's text.
public uint2 token_text(TokenBody b, uint token)
{
    RtJobToken t = job_token(token);
    uint end = token + 1u < b.first + b.count ? job_token(token + 1u).start : b.text_end;
    uint start = token == b.first ? b.text_start : t.start;
    return uint2(start, max(end, start));
}
