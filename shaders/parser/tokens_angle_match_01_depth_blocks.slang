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
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_angle;

RWStructuredBuffer<int> angle_match_depth;
RWStructuredBuffer<int> angle_match_block_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;
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

bool is_angle_open(uint kind)
{
    return kind == TK_LT || kind == TK_TYPE_ARG_LT || kind == TK_GENERIC_PARAM_LT ||
           kind == TK_BOUND_TYPE_ARG_LT || kind == TK_PATH_TYPE_ARG_LT;
}

bool is_angle_close(uint kind)
{
    return kind == TK_GT || kind == TK_TYPE_ARG_GT || kind == TK_GENERIC_PARAM_GT ||
           kind == TK_BOUND_TYPE_ARG_GT || kind == TK_PATH_TYPE_ARG_GT;
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
        int depth_before = block_prefix_angle[block_idx] + depth_angle_inblock[token_i];
        if (is_angle_open(kind))
            event_depth = depth_before;
        else if (is_angle_close(kind))
            event_depth = depth_before - 1;
        angle_match_depth[token_i] = event_depth;
    }
    else if (token_i < gParams.n_tokens)
    {
        angle_match_depth[token_i] = INF;
    }

    int block_min = prefix_scan_inclusive<int, PrefixScanI32Min, 256>(
        lane,
        event_depth,
        local_depth);

    if (lane == WG_SIZE - 1u)
        angle_match_block_min[block_idx] = block_min;
}
