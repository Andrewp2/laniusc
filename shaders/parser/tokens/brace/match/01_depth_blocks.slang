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
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> block_prefix_brace;

RWStructuredBuffer<int> brace_match_depth;
RWStructuredBuffer<int> brace_match_block_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const int INF = 2147483647;

groupshared int local_depth[256];

public struct PrefixScanI32Min : IPrefixScanOp<int>
{
    public static int identity()
    {
        return INF;
    }

    public static int combine(int left, int right)
    {
        return min(left, right);
    }
}

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
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
        int depth_before = block_prefix_brace[block_idx] + depth_brace_inblock[token_i];
        if (kind == TK_LBRACE)
            event_depth = depth_before;
        else if (kind == TK_RBRACE)
            event_depth = depth_before - 1;
        brace_match_depth[token_i] = event_depth;
    }
    else if (token_i < gParams.n_tokens)
    {
        brace_match_depth[token_i] = INF;
    }

    int block_min = prefix_scan_inclusive<int, PrefixScanI32Min, 256>(
        lane,
        event_depth,
        local_depth);

    if (lane == WG_SIZE - 1u)
        brace_match_block_min[block_idx] = block_min;
}
