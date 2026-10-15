import gpu_index;
import hir_records;
import generated_token_ids;

// Source byte spans of generic callable bodies, for concrete instance copies.
// The host copies these byte ranges into an instance unit and renames each
// copy; it never lexes or inspects the text. One record per kind-3 row whose
// lexical environment has generic parameters and that is a top-level
// function or a method of an inherent impl. Trait members and trait-impl
// methods have no record: they replay in their original scope.
struct Params {
    uint n_tokens; uint source_len; uint n_hir_nodes;
    uint n_source_files; uint parser_feature_flags;
};
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
// The checked native callable symbol of each function row (00_project).
StructuredBuffer<uint> semantic_function_native_symbol_by_hir;
// Counts every eligible row, even past capacity: the host rejects overflow.
RWStructuredBuffer<uint> retained_owner_span_count;
// OWNER_SPAN_WORDS words per record, in atomic order (the host sorts):
// function row, function token_start, name byte start, body byte end
// (exclusive), impl row, `impl` keyword byte, byte after the impl body's
// opening brace, native symbol. Impl fields are INVALID for a top-level
// function.
RWStructuredBuffer<uint> retained_owner_spans;

static const uint INVALID = 0xffffffffu;
static const uint OWNER_SPAN_WORDS = 8u;
static const uint HIR_FN = 3u;
static const uint HIR_FILE = 1u;
static const uint HIR_IMPL = 35u;
static const uint HIR_IMPL_INHERENT = 1u;
static const uint HIR_ITEM_KIND_FN = 4u;
// An impl header is short; the scan stops at the method's own first token.
static const uint MAX_HEADER_TOKENS = 4096u;

uint active_tokens()
{
    uint rows; uint stride;
    token_words.GetDimensions(rows, stride);
    return min(min(token_count[0u], gParams.n_tokens), rows);
}

bool token_end_byte(uint token, uint tokens, out uint end)
{
    end = INVALID;
    if (token >= tokens) return false;
    TokenIn word = token_words[token];
    if (word.start > gParams.source_len || word.len > gParams.source_len - word.start)
        return false;
    end = word.start + word.len;
    return true;
}

// Same rule as codegen's function_has_generic_environment: parameters of any
// lexical ancestor make the body generic.
bool has_generic_environment(uint row, uint count)
{
    uint owner = row;
    for (uint depth = 0u; depth < count; depth++)
    {
        if (compact_generic_param_ranges[owner].count != 0u) return true;
        uint parent = compact_hir_core[owner].parent;
        if (parent == INVALID || parent >= owner) return false;
        owner = parent;
    }
    return false;
}

// The nearest enclosing impl, or INVALID for a top-level item. A trait or any
// other container also yields INVALID through `container`.
uint enclosing_impl(uint row, uint count, out bool other_container)
{
    other_container = false;
    uint node = compact_hir_core[row].parent;
    for (uint depth = 0u; depth < count && node < count; depth++)
    {
        uint kind = compact_hir_core[node].kind;
        if (kind == HIR_IMPL) return node;
        if (kind == HIR_FILE) return INVALID;
        if (kind == HIR_FN || kind == 2u) { other_container = true; return INVALID; }
        uint parent = compact_hir_core[node].parent;
        if (parent == INVALID || parent >= node) return INVALID;
        node = parent;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint hir_rows; uint stride;
    compact_hir_core.GetDimensions(hir_rows, stride);
    uint count = min(min(compact_hir_count[0u], gParams.n_hir_nodes), hir_rows);
    if (row >= count) return;
    HirCore core = compact_hir_core[row];
    if (core.kind != HIR_FN || !has_generic_environment(row, count)) return;
    HirPayload payload = compact_hir_payload[row];
    bool other_container;
    uint impl_row = enclosing_impl(row, count, other_container);
    if (other_container) return;
    if (impl_row == INVALID && payload.a != HIR_ITEM_KIND_FN) return;
    if (impl_row != INVALID && compact_hir_payload[impl_row].a != HIR_IMPL_INHERENT) return;

    uint tokens = active_tokens();
    uint name_token = payload.b;
    uint name_byte = name_token < tokens ? token_words[name_token].start : INVALID;
    uint end_byte;
    bool spans = name_byte != INVALID && core.token_end != INVALID && core.token_end > name_token &&
        token_end_byte(core.token_end - 1u, tokens, end_byte) && end_byte > name_byte;
    uint keyword_byte = INVALID;
    uint brace_end = INVALID;
    if (spans && impl_row != INVALID)
    {
        uint first = compact_hir_core[impl_row].token_start;
        uint keyword = INVALID;
        uint limit = min(core.token_start, tokens);
        for (uint step = 0u; step < MAX_HEADER_TOKENS && first + step < limit; step++)
        {
            uint token = first + step;
            uint kind = token_words[token].kind;
            if (keyword == INVALID)
            {
                if (kind == TK_IMPL) { keyword = token; keyword_byte = token_words[token].start; }
                continue;
            }
            if (kind == TK_IMPL_LBRACE || kind == TK_LBRACE)
            {
                if (!token_end_byte(token, tokens, brace_end)) brace_end = INVALID;
                break;
            }
        }
        spans = keyword_byte != INVALID && brace_end != INVALID && brace_end <= name_byte;
    }
    uint slot;
    InterlockedAdd(retained_owner_span_count[0u], 1u, slot);
    uint words; uint word_stride;
    retained_owner_spans.GetDimensions(words, word_stride);
    if (slot >= words / OWNER_SPAN_WORDS) return;
    uint base = slot * OWNER_SPAN_WORDS;
    retained_owner_spans[base] = row;
    retained_owner_spans[base + 1u] = core.token_start;
    // A malformed relation keeps its row with INVALID spans; the host refuses
    // to copy it and replays that body in its original scope instead.
    retained_owner_spans[base + 2u] = spans ? name_byte : INVALID;
    retained_owner_spans[base + 3u] = spans ? end_byte : INVALID;
    retained_owner_spans[base + 4u] = impl_row;
    retained_owner_spans[base + 5u] = spans ? keyword_byte : INVALID;
    retained_owner_spans[base + 6u] = spans ? brace_end : INVALID;
    uint symbols;
    semantic_function_native_symbol_by_hir.GetDimensions(symbols, word_stride);
    retained_owner_spans[base + 7u] = row < symbols ? semantic_function_native_symbol_by_hir[row] : INVALID;
}
