// Export step clear_retained_body_text: one lane per job token. Zeroes the words of its body's
// text block that the token's bytes cover (retained_token_body_lookup.slang), so step copy_retained_body_text
// can OR the bytes in. Every word of a block is covered by some token.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;
import type_checker.retention.export_rows.retained_body_source_tables;
import type_checker.retention.export_rows.retained_token_body_lookup;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = export_lane(dtid);
    if (token >= job_token_rows()) return;
    TokenBody b = token_body(token);
    if (b.segment == RT_INVALID) return;
    uint text_base = rt_segments[b.segment * RT_SEG_WORDS + 5u].x;
    if (text_base == RT_INVALID) return;
    uint2 range = token_text(b, token);
    if (range.y == range.x) return;
    uint first_word = (range.x - b.text_start) >> 2u;
    uint last_word = (range.y - 1u - b.text_start) >> 2u;
    for (uint w = first_word; w <= last_word; w++) rt_seg_bytes[text_base + w] = 0u;
}
