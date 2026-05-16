// Paper-aligned name extraction foundation.
//
// GPU-only scheduling contract:
// - Dispatch after a GPU exclusive prefix sum over name_lexeme_flag.
// - This pass scatters compact NameSpan records for the radix name sorter.
// - String lexemes use their raw interior byte span. Escape interpretation is a
//   later string-literal semantic step and is not part of module resolution.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> name_lexeme_flag;
StructuredBuffer<uint> name_lexeme_kind;
StructuredBuffer<uint> name_lexeme_prefix;
StructuredBuffer<uint> language_symbol_start;
StructuredBuffer<uint> language_symbol_len;

RWStructuredBuffer<NameSpan> name_spans;
RWStructuredBuffer<uint> name_order_in;
RWStructuredBuffer<uint> name_id_by_token;
RWStructuredBuffer<uint> name_count_out;
RWStructuredBuffer<uint> status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_NAME_RADIX_BYTES = 64u;
static const uint MAX_NAME_RADIX_ITEMS = 65536u;
static const uint ERR_NAME_LIMIT = 11u;
static const uint LANGUAGE_SYMBOL_COUNT = 19u;

static const uint NAME_KIND_NONE = 0u;
static const uint NAME_KIND_IDENTIFIER = 1u;
static const uint NAME_KIND_STRING = 2u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint token_start(uint i)
{
    return i < active_token_count() ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    return i < active_token_count() ? token_words[i].len : 0u;
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

NameSpan make_name_span(uint token_i, uint kind)
{
    uint start = token_start(token_i);
    uint len = token_len(token_i);
    if (kind == NAME_KIND_STRING && len >= 2u)
    {
        start += 1u;
        len -= 2u;
    }

    NameSpan span;
    span.start = start;
    span.len = len;
    span.kind = kind;
    span.token_index = token_i;
    return span;
}

NameSpan make_language_symbol_span(uint symbol_i)
{
    NameSpan span;
    span.start = language_symbol_start[symbol_i];
    span.len = language_symbol_len[symbol_i];
    span.kind = NAME_KIND_LANGUAGE_SYMBOL;
    span.token_index = symbol_i;
    return span;
}

uint compact_token_name_count()
{
    uint active = active_token_count();
    if (active == 0u)
        return 0u;
    uint last = active - 1u;
    return name_lexeme_prefix[last] + name_lexeme_flag[last];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    name_id_by_token[i] = INVALID;
    if (i == 0u && gParams.n_tokens + LANGUAGE_SYMBOL_COUNT > MAX_NAME_RADIX_ITEMS)
        record_error(0u, ERR_NAME_LIMIT, MAX_NAME_RADIX_ITEMS);

    uint active = active_token_count();
    uint token_name_count = compact_token_name_count();
    if (i == 0u)
    {
        [unroll]
        for (uint symbol_i = 0u; symbol_i < LANGUAGE_SYMBOL_COUNT; symbol_i += 1u)
        {
            uint slot = token_name_count + symbol_i;
            NameSpan span = make_language_symbol_span(symbol_i);
            if (span.len > MAX_NAME_RADIX_BYTES)
                record_error(0u, ERR_NAME_LIMIT, span.len);
            name_spans[slot] = span;
            name_order_in[slot] = slot;
        }
        name_count_out[0] = token_name_count + LANGUAGE_SYMBOL_COUNT;
    }

    if (i >= active)
        return;

    uint flag = name_lexeme_flag[i];
    uint prefix = name_lexeme_prefix[i];
    if (flag != 0u)
    {
        uint slot = prefix;
        NameSpan span = make_name_span(i, name_lexeme_kind[i]);
        if (span.len > MAX_NAME_RADIX_BYTES)
            record_error(i, ERR_NAME_LIMIT, span.len);
        name_spans[slot] = span;
        name_order_in[slot] = slot;
    }
}
