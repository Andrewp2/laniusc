import gpu_index;
import hir_records;

struct Params {
    uint n_tokens; uint source_len; uint n_hir_nodes;
    uint n_source_files; uint parser_feature_flags;
};
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> retained_callable_flag;
StructuredBuffer<uint> retained_callable_prefix;
// Three scalar words per retained row: call HIR, packed source byte start,
// and byte length of the exact token at that call's HIR token_start.
RWStructuredBuffer<uint> retained_callable_records;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (row >= min(compact_hir_count[0u], gParams.n_hir_nodes) ||
        retained_callable_flag[row] == 0u) return;
    uint words; uint stride;
    retained_callable_records.GetDimensions(words, stride);
    uint output_row = retained_callable_prefix[row];
    if (output_row >= words / 3u) return;
    uint first = output_row * 3u;
    retained_callable_records[first] = row;
    // Preserve the call even if its source relation is malformed. The host
    // rejects this sentinel instead of silently losing an accepted call fact.
    retained_callable_records[first + 1u] = 0xffffffffu;
    retained_callable_records[first + 2u] = 0u;

    uint hir_rows; uint token_rows; uint count_rows;
    compact_hir_core.GetDimensions(hir_rows, stride);
    token_words.GetDimensions(token_rows, stride);
    token_count.GetDimensions(count_rows, stride);
    if (row >= hir_rows || count_rows == 0u) return;
    uint token = compact_hir_core[row].token_start;
    // n_tokens is capacity; the count buffer owns the active token length.
    if (token >= min(token_count[0u], gParams.n_tokens) || token >= token_rows) return;
    TokenIn source = token_words[token];
    if (source.len == 0u || source.start > gParams.source_len ||
        source.len > gParams.source_len - source.start) return;
    retained_callable_records[first + 1u] = source.start;
    retained_callable_records[first + 2u] = source.len;
}
