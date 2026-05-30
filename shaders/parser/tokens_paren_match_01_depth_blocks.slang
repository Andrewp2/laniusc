import prefix_scan;

struct Params
{
    uint n_tokens;
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
StructuredBuffer<int> block_prefix_paren;

RWStructuredBuffer<int> paren_match_depth;
RWStructuredBuffer<int> paren_match_block_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const int INF = 2147483647;

groupshared int local_depth[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

bool is_paren_open(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_paren_close(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    uint token_i = block_idx * WG_SIZE + lane;
    uint count = active_token_count();

    int event_depth = INF;
    if (token_i < gParams.n_tokens && token_i < count)
    {
        uint kind = token_words[token_i].kind;
        int depth_before = block_prefix_paren[block_idx] + depth_paren_inblock[token_i];
        if (is_paren_open(kind))
            event_depth = depth_before;
        else if (is_paren_close(kind))
            event_depth = depth_before - 1;
        paren_match_depth[token_i] = event_depth;
    }
    else if (token_i < gParams.n_tokens)
    {
        paren_match_depth[token_i] = INF;
    }

    local_depth[lane] = event_depth;
    GroupMemoryBarrierWithGroupSync();

    [unroll]
    for (uint step = WG_SIZE >> 1u; step > 0u; step >>= 1u)
    {
        if (lane < step)
            local_depth[lane] = min(local_depth[lane], local_depth[lane + step]);
        GroupMemoryBarrierWithGroupSync();
    }

    if (lane == 0u)
        paren_match_block_min[block_idx] = local_depth[0u];
}
