// Export step copy_retained_body_text: one lane per job token of a retained body. Copies the
// token's bytes into its body's text block and writes its token record
//   (kind, byte start in the body text, byte length, name hash)
// The name hash is the FNV-1a hash of the token's own bytes, so an
// identifier compares across units without the job's name interner.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_rows.retained_body_source_tables;
import type_checker.retention.export_rows.retained_token_body_lookup;

public void copy_retained_body_text(uint token)
{
    if (token >= job_token_rows()) return;
    TokenBody b = token_body(token);
    if (b.segment == RT_INVALID) return;
    uint4 s4 = rt_segments[b.segment * RT_SEG_WORDS + 4u];
    uint text_base = rt_segments[b.segment * RT_SEG_WORDS + 5u].x;
    if (text_base == RT_INVALID || s4.w == RT_INVALID) return;
    uint2 range = token_text(b, token);
    for (uint at = range.x; at < range.y; at++)
    {
        uint rel = at - b.text_start;
        uint byte = job_source_byte(at);
        if (byte != 0u) InterlockedOr(rt_seg_bytes[text_base + (rel >> 2u)], byte << ((rel & 3u) * 8u));
    }
    RtJobToken t = job_token(token);
    uint hash = 0x811c9dc5u;
    for (uint i = 0u; i < t.len; i++) hash = (hash ^ job_source_byte(t.start + i)) * 0x01000193u;
    rt_seg_tokens[s4.w + token - b.first] = uint4(t.kind, t.start - b.text_start, t.len, hash);
}
