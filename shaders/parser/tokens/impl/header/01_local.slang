// Impl-header context block summaries for token retagging.
//
// This pass records the latest raw `impl` header start in each token block,
// reset by item/statement boundaries. A later prefix-scan/apply pass lets
// token classifiers consume impl-header context without walking source tokens.

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
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> block_prefix_bracket;

RWStructuredBuffer<uint> statement_event_block;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_SEMICOLON = 37u;
static const uint TK_IMPL = 98u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;

static const uint IMPL_HEADER_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

#include "event.slang"

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
    uint event = token_i < count ? impl_event_for(token_i, kind) : 0u;
    uint prefix = prefix_scan_u32_max_256(lane, event);
    if (lane + 1u == WG_SIZE)
        statement_event_block[block_idx] = prefix;
}
