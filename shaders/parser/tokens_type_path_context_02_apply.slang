// Apply prefix-scanned qualified type-path context rows.

import prefix_scan;

struct Params
{
    uint n_tokens;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<uint> semantic_token_kinds;
StructuredBuffer<uint> token_impl_context_event;
StructuredBuffer<uint> statement_event_block_prefix;

RWStructuredBuffer<uint> token_type_path_context_kind;

groupshared uint type_path_context_prefix_values[256];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_IDENT = 1u;
static const uint TK_COLON = 38u;
static const uint TK_IMPL = 98u;
static const uint TK_TYPE_COLON = 108u;
static const uint TK_TYPE_ALIAS_ASSIGN = 110u;
static const uint TK_RETURN_ARROW = 112u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_COMMA = 135u;
static const uint TK_TYPE_AMPERSAND = 144u;
static const uint TK_BOUND_PLUS = 145u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_BOUND_COLON = 107u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_BOUND_TYPE_IDENT = 174u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_COMMA = 177u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_COMMA = 186u;
static const uint IMPL_HEADER_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint raw_kind_at_token(uint token_i, uint count)
{
    return token_i < count ? token_words[token_i].kind : 0u;
}

uint raw_kind_at_parser(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count)
        return 0u;
    return raw_kind_at_token(parser_i - 1u, count);
}

uint semantic_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count + 1u)
        return 0u;
    return semantic_token_kinds[parser_i];
}

uint previous_symbol_kind(uint parser_i, uint count)
{
    uint prev_parser_i = parser_i - 1u;
    uint prev_raw = raw_kind_at_parser(prev_parser_i, count);
    if (prev_raw == TK_IDENT)
        return prev_raw;
    return semantic_kind_at(prev_parser_i, count);
}

bool impl_type_context_before(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    return token_i < count &&
           token_i < gParams.n_tokens &&
           (token_impl_context_event[token_i] & 0xffu) == IMPL_HEADER_CONTEXT;
}

uint direct_type_path_context_kind(uint parser_i, uint count)
{
    uint prev = previous_symbol_kind(parser_i, count);
    if (prev == TK_BOUND_COLON || prev == TK_BOUND_PLUS ||
        prev == TK_BOUND_TYPE_ARG_LT || prev == TK_BOUND_TYPE_ARG_COMMA)
        return TK_BOUND_TYPE_IDENT;
    if (prev == TK_TYPE_COLON || prev == TK_RETURN_ARROW ||
        prev == TK_TYPE_ALIAS_ASSIGN || prev == TK_TYPE_AMPERSAND ||
        prev == TK_TYPE_ARG_LT || prev == TK_TYPE_ARG_COMMA ||
        prev == TK_PATH_TYPE_ARG_LT || prev == TK_PATH_TYPE_ARG_COMMA ||
        prev == TK_TYPE_ARRAY_LBRACKET || impl_type_context_before(parser_i, count) ||
        raw_kind_at_parser(parser_i - 1u, count) == TK_IMPL)
        return TK_TYPE_IDENT;
    return 0u;
}

bool path_continuation_ident(uint token_i, uint count)
{
    return raw_kind_at_token(token_i, count) == TK_IDENT &&
           token_i >= 3u &&
           raw_kind_at_token(token_i - 1u, count) == TK_COLON &&
           raw_kind_at_token(token_i - 2u, count) == TK_COLON &&
           raw_kind_at_token(token_i - 3u, count) == TK_IDENT;
}

bool path_separator_colon(uint token_i, uint count)
{
    if (raw_kind_at_token(token_i, count) != TK_COLON)
        return false;
    bool first = token_i > 0u &&
                 raw_kind_at_token(token_i - 1u, count) == TK_IDENT &&
                 raw_kind_at_token(token_i + 1u, count) == TK_COLON &&
                 raw_kind_at_token(token_i + 2u, count) == TK_IDENT;
    bool second = token_i >= 2u &&
                  raw_kind_at_token(token_i - 2u, count) == TK_IDENT &&
                  raw_kind_at_token(token_i - 1u, count) == TK_COLON &&
                  raw_kind_at_token(token_i + 1u, count) == TK_IDENT;
    return first || second;
}

uint encode_context_event(uint token_i, uint payload)
{
    return ((token_i + 1u) << 8u) | (payload & 0xffu);
}

uint context_event_for(uint token_i, uint count)
{
    uint kind = raw_kind_at_token(token_i, count);
    if (kind == TK_IDENT)
    {
        if (path_continuation_ident(token_i, count))
            return 0u;
        return encode_context_event(
            token_i,
            direct_type_path_context_kind(token_i + 1u, count));
    }
    if (path_separator_colon(token_i, count))
        return 0u;
    return encode_context_event(token_i, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint token_i = block_idx * WG_SIZE + lane;
    uint count = active_token_count();

    uint event = token_i < count ? context_event_for(token_i, count) : 0u;
    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        event,
        type_path_context_prefix_values);
    uint local_prefix = type_path_context_prefix_values[lane];
    uint prefix = max(statement_event_block_prefix[block_idx], local_prefix);
    uint context = token_i < count ? (prefix & 0xffu) : 0u;
    if (token_i < gParams.n_tokens)
        token_type_path_context_kind[token_i] = context;
}
