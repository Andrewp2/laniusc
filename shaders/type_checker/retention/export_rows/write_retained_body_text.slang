import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_rows.retained_body_source_tables;

// A workgroup owns the segment. Each text word and each token record has
// one writer, including words that span a token boundary or whitespace.
public void write_retained_body_text(uint ordinal, uint segment, uint lane, uint lanes)
{
    uint tokens = rt_segments[segment * RT_SEG_WORDS + 2u].w;
    uint4 source = rt_segments[segment * RT_SEG_WORDS + 4u];
    uint text_base = rt_segments[segment * RT_SEG_WORDS + 5u].x;
    if (tokens == 0u || text_base == RT_INVALID || source.w == RT_INVALID) return;
    uint first = rt_x_seg_token[ordinal];
    uint start = job_token(first).start;
    uint words = (source.z + 3u) >> 2u;
    for (uint w = lane; w < words; w += lanes)
    {
        uint offset = w * 4u;
        rt_seg_bytes[text_base + w] = job_source_word(start + offset, min(4u, source.z - offset));
    }
    for (uint i = lane; i < tokens; i += lanes)
    {
        RtJobToken t = job_token(first + i);
        uint hash = 0x811c9dc5u;
        for (uint byte = 0u; byte < t.len; ++byte)
            hash = (hash ^ job_source_byte(t.start + byte)) * 0x01000193u;
        rt_seg_tokens[source.w + i] = uint4(t.kind, t.start - start, t.len, hash);
    }
}
