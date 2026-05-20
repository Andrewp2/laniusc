// Token delimiter metadata for semantic retagging.
//
// This pass computes raw brace depth before each token. A later pass consumes
// the global block prefix to record top-level brace owners.

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

RWStructuredBuffer<int> depth_brace_inblock;
RWStructuredBuffer<int> block_sum_brace;
RWStructuredBuffer<uint> top_brace_owner_block;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

int brace_delta(uint kind)
{
    if (kind == TK_LBRACE)
        return 1;
    if (kind == TK_RBRACE)
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
    uint token_i = block_idx * WG_SIZE + lane;
    uint count = active_token_count();
    uint kind = token_i < count ? token_words[token_i].kind : 0u;

    int delta = brace_delta(kind);
    int inclusive_depth = prefix_scan_i32_256(lane, delta);
    if (token_i < gParams.n_tokens)
        depth_brace_inblock[token_i] = inclusive_depth - delta;
    if (lane + 1u == WG_SIZE)
        block_sum_brace[block_idx] = inclusive_depth;

    if (lane + 1u == WG_SIZE)
        top_brace_owner_block[block_idx] = 0u;
}
