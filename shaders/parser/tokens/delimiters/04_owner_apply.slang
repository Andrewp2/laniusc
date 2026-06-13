// Apply prefix-scanned brace-owner header context.

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
StructuredBuffer<int> depth_paren_inblock;
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> block_prefix_angle;
StructuredBuffer<uint> token_impl_context_event;
StructuredBuffer<uint> top_brace_owner_block_prefix;

RWStructuredBuffer<uint> top_brace_owner_block;
RWStructuredBuffer<uint> brace_semantic_kind;
RWStructuredBuffer<uint> statement_event_block;

groupshared uint owner_header_prefix_values[256];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_RPAREN = 5u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint TK_IMPL_LBRACE = 121u;
static const uint TK_TRAIT_LBRACE = 123u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_DECL_LBRACE = 127u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_FN_BLOCK_LBRACE = 149u;
static const uint TK_DEFERRED_FN_BLOCK_LBRACE = 0x80000000u;
static const uint IMPL_HEADER_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint raw_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count)
        return 0u;
    return token_words[parser_i - 1u].kind;
}

bool semantic_token_ends_primary(uint kind)
{
    return kind == TK_IDENT ||
           kind == TK_INT ||
           kind == TK_RPAREN ||
           kind == TK_RBRACKET ||
           kind == TK_STRING ||
           kind == TK_FLOAT ||
           kind == TK_CHAR ||
           kind == TK_TRUE ||
           kind == TK_FALSE ||
           kind == TK_SELF_VALUE;
}

uint encode_owner_event(uint token_i, uint owner_kind)
{
    return ((token_i + 1u) << 8u) | (owner_kind & 0xffu);
}

uint decode_owner_kind(uint event)
{
    return event & 0xffu;
}

bool item_header_delimiter_context(int paren_depth, int bracket_depth, int angle_depth)
{
    // Raw `<`/`>` tokens include comparison operators before semantic retagging.
    // Do not let an earlier comparison expression suppress a later top-level
    // item header; generic header structure is recovered by dedicated angle
    // retagging passes.
    return paren_depth == 0 && bracket_depth == 0;
}

bool header_reset_delimiter_context(int paren_depth, int bracket_depth, int angle_depth)
{
    return paren_depth == 0 && bracket_depth == 0;
}

bool recorded_impl_header_context_before_token(uint token_i, uint count)
{
    return token_i < count &&
           token_i < gParams.n_tokens &&
           (token_impl_context_event[token_i] & 0xffu) == IMPL_HEADER_CONTEXT;
}

uint owner_header_event_for(
    uint token_i,
    uint count,
    uint kind,
    int paren_depth,
    int bracket_depth,
    int angle_depth)
{
    bool item_header_context = item_header_delimiter_context(
        paren_depth,
        bracket_depth,
        angle_depth);

    if (item_header_context && kind == TK_FN)
        return encode_owner_event(token_i, TK_FN_BLOCK_LBRACE);
    if (item_header_context && kind == TK_IMPL)
        return encode_owner_event(token_i, TK_IMPL_LBRACE);
    if (item_header_context && kind == TK_TRAIT)
        return encode_owner_event(token_i, TK_TRAIT_LBRACE);
    if (item_header_context && kind == TK_STRUCT)
        return encode_owner_event(token_i, TK_STRUCT_DECL_LBRACE);
    if (item_header_context && kind == TK_ENUM)
        return encode_owner_event(token_i, TK_ENUM_LBRACE);
    if (kind == TK_MATCH)
        return encode_owner_event(token_i, TK_MATCH_LBRACE);
    if (kind == TK_FOR)
    {
        uint owner = recorded_impl_header_context_before_token(token_i, count)
            ? TK_IMPL_LBRACE
            : TK_LBRACE;
        return encode_owner_event(token_i, owner);
    }
    if (kind == TK_IF)
        return encode_owner_event(token_i, TK_IF_LBRACE);
    if (kind == TK_ELSE || kind == TK_WHILE)
        return encode_owner_event(token_i, TK_LBRACE);
    if (kind == TK_SEMICOLON &&
        header_reset_delimiter_context(paren_depth, bracket_depth, angle_depth))
        return encode_owner_event(token_i, 0u);
    if (kind == TK_LBRACE || kind == TK_RBRACE)
        return encode_owner_event(token_i, 0u);
    return 0u;
}

uint brace_open_kind_for(uint parser_i, uint count, uint header_context)
{
    uint owner = decode_owner_kind(header_context);
    if (owner != 0u)
        return owner;

    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    if (semantic_token_ends_primary(prev_raw))
        return TK_STRUCT_LIT_LBRACE;

    return TK_LBRACE;
}

bool is_statement_starter(uint kind)
{
    return kind == TK_IMPORT ||
           kind == TK_MODULE ||
           kind == TK_EXTERN ||
           kind == TK_TYPE ||
           kind == TK_CONST ||
           kind == TK_LET ||
           kind == TK_RETURN ||
           kind == TK_IF ||
           kind == TK_ELSE ||
           kind == TK_WHILE ||
           kind == TK_FOR ||
           kind == TK_BREAK ||
           kind == TK_CONTINUE ||
           kind == TK_FN ||
           kind == TK_ENUM ||
           kind == TK_STRUCT ||
           kind == TK_IMPL ||
           kind == TK_TRAIT;
}

bool is_statement_reset_boundary(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE;
}

uint statement_event_for(uint token_i, uint kind, int global_bracket_depth_before)
{
    if (global_bracket_depth_before != 0)
        return 0u;
    if (is_statement_starter(kind))
        return ((token_i + 1u) << 8u) | (kind & 0xffu);
    if (is_statement_reset_boundary(kind))
        return (token_i + 1u) << 8u;
    return 0u;
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
    uint parser_i = token_i + 1u;
    uint kind = token_i < count ? token_words[token_i].kind : 0u;
    int paren_depth = token_i < gParams.n_tokens
        ? block_prefix_paren[block_idx] + depth_paren_inblock[token_i]
        : 0;
    int brace_depth = token_i < gParams.n_tokens
        ? block_prefix_brace[block_idx] + depth_brace_inblock[token_i]
        : 0;
    int bracket_depth = token_i < gParams.n_tokens
        ? block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i]
        : 0;
    int angle_depth = token_i < gParams.n_tokens
        ? block_prefix_angle[block_idx] + depth_angle_inblock[token_i]
        : 0;

    uint header_event = token_i < count
        ? owner_header_event_for(token_i, count, kind, paren_depth, bracket_depth, angle_depth)
        : 0u;
    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        header_event,
        owner_header_prefix_values);
    uint local_header_before = lane == 0u ? 0u : owner_header_prefix_values[lane - 1u];
    uint header_before = max(
        top_brace_owner_block_prefix[block_idx],
        local_header_before);

    uint owner_event = 0u;
    uint open_kind = 0u;
    if (token_i < count && kind == TK_LBRACE)
    {
        uint candidate = brace_open_kind_for(parser_i, count, header_before);
        bool defer_impl_method_body = brace_depth != 0 && candidate == TK_FN_BLOCK_LBRACE;
        open_kind = defer_impl_method_body ? TK_DEFERRED_FN_BLOCK_LBRACE : candidate;
        if (brace_depth == 0)
            owner_event = encode_owner_event(token_i, open_kind);
    }

    if (token_i < gParams.n_tokens)
        brace_semantic_kind[token_i] = open_kind;

    uint owner_prefix = prefix_scan_u32_max_256(lane, owner_event);
    if (lane + 1u == WG_SIZE)
        top_brace_owner_block[block_idx] = owner_prefix;

    uint statement_event = token_i < count
        ? statement_event_for(token_i, kind, bracket_depth)
        : 0u;
    uint statement_prefix = prefix_scan_u32_max_256(lane, statement_event);
    if (lane + 1u == WG_SIZE)
        statement_event_block[block_idx] = statement_prefix;
}
