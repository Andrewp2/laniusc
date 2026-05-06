// Syntax delimiter block-local depth scans for (), [], and {} classes.

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
StructuredBuffer<uint> token_count;

RWStructuredBuffer<int> depth_paren_inblock;
RWStructuredBuffer<int> depth_bracket_inblock;
RWStructuredBuffer<int> depth_brace_inblock;
RWStructuredBuffer<int> block_sum_paren;
RWStructuredBuffer<int> block_sum_bracket;
RWStructuredBuffer<int> block_sum_brace;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

int paren_delta(uint kind)
{
    if (kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
        kind == TK_PARAM_LPAREN)
        return 1;
    if (kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
        kind == TK_PARAM_RPAREN)
        return -1;
    return 0;
}

int bracket_delta(uint kind)
{
    if (kind == TK_LBRACKET || kind == TK_INDEX_LBRACKET || kind == TK_ARRAY_LBRACKET ||
        kind == TK_TYPE_ARRAY_LBRACKET)
        return 1;
    if (kind == TK_RBRACKET || kind == TK_INDEX_RBRACKET || kind == TK_ARRAY_RBRACKET ||
        kind == TK_TYPE_ARRAY_RBRACKET)
        return -1;
    return 0;
}

int brace_delta(uint kind)
{
    if (kind == TK_LBRACE || kind == TK_IF_LBRACE)
        return 1;
    if (kind == TK_RBRACE || kind == TK_IF_RBRACE)
        return -1;
    return 0;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint i = block_idx * WG_SIZE + lane;
    uint n = active_token_count();
    uint kind = i < n ? token_words[i].kind : 0u;

    int paren = paren_delta(kind);
    int paren_inc = prefix_scan_i32_256(lane, paren);
    if (i < gParams.n_tokens)
        depth_paren_inblock[i] = paren_inc - paren;
    if (lane + 1u == WG_SIZE)
        block_sum_paren[block_idx] = paren_inc;

    int bracket = bracket_delta(kind);
    int bracket_inc = prefix_scan_i32_256(lane, bracket);
    if (i < gParams.n_tokens)
        depth_bracket_inblock[i] = bracket_inc - bracket;
    if (lane + 1u == WG_SIZE)
        block_sum_bracket[block_idx] = bracket_inc;

    int brace = brace_delta(kind);
    int brace_inc = prefix_scan_i32_256(lane, brace);
    if (i < gParams.n_tokens)
        depth_brace_inblock[i] = brace_inc - brace;
    if (lane + 1u == WG_SIZE)
        block_sum_brace[block_idx] = brace_inc;
}
