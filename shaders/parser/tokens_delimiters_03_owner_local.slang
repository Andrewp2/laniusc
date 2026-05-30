// Block-local brace-owner header summaries.
//
// This pass publishes the latest raw header/reset event in each token block.
// The normal delimiter block scan turns those block summaries into a prefix
// context. The apply pass then classifies brace owners without walking backward
// through source tokens.

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
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> block_prefix_angle;
StructuredBuffer<uint> token_impl_context_event;

RWStructuredBuffer<uint> top_brace_owner_block;
RWStructuredBuffer<uint> statement_event_block;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_SEMICOLON = 37u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_FN = 67u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint TK_IMPL_LBRACE = 121u;
static const uint TK_TRAIT_LBRACE = 123u;
static const uint TK_STRUCT_DECL_LBRACE = 127u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_FN_BLOCK_LBRACE = 149u;
static const uint IMPL_HEADER_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint encode_owner_event(uint token_i, uint owner_kind)
{
    return ((token_i + 1u) << 8u) | (owner_kind & 0xffu);
}

bool item_header_delimiter_context(int paren_depth, int bracket_depth, int angle_depth)
{
    return paren_depth == 0 && bracket_depth == 0 && angle_depth == 0;
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
    if (kind == TK_IF || kind == TK_ELSE || kind == TK_WHILE)
        return encode_owner_event(token_i, TK_LBRACE);
    if (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE)
        return encode_owner_event(token_i, 0u);
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
    uint kind = token_i < count ? token_words[token_i].kind : 0u;
    int paren_depth = token_i < gParams.n_tokens
        ? block_prefix_paren[block_idx] + depth_paren_inblock[token_i]
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
    uint header_prefix = prefix_scan_u32_max_256(lane, header_event);
    if (lane + 1u == WG_SIZE)
    {
        top_brace_owner_block[block_idx] = header_prefix;
        statement_event_block[block_idx] = 0u;
    }
}
