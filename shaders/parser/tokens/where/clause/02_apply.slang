// Apply prefix-scanned where-clause context rows.

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
StructuredBuffer<uint> statement_event_block_prefix;

RWStructuredBuffer<uint> token_where_context_event;

groupshared uint where_prefix_values[256];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_WHERE = 104u;

static const uint WHERE_CLAUSE_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint encode_where_event(uint token_i, uint payload)
{
    return ((token_i + 1u) << 8u) | (payload & 0xffu);
}

uint where_event_for(uint token_i, uint kind)
{
    if (kind == TK_WHERE)
        return encode_where_event(token_i, WHERE_CLAUSE_CONTEXT);
    if (kind == TK_LBRACE || kind == TK_RBRACE || kind == TK_SEMICOLON)
        return encode_where_event(token_i, 0u);
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
    uint event = token_i < count ? where_event_for(token_i, kind) : 0u;
    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        event,
        where_prefix_values);

    uint local_before = lane == 0u ? 0u : where_prefix_values[lane - 1u];
    uint before = max(statement_event_block_prefix[block_idx], local_before);
    if (token_i < gParams.n_tokens)
        token_where_context_event[token_i] = before;
}
