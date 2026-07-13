// Publish token-local stack-effect summaries for contextual `>>` splitting.
// Each token is one independent input element; the workgroup scan composes the
// associative (sum, minimum-prefix) monoid.

import prefix_scan;

struct Params { uint n_tokens; uint n_blocks; uint scan_step; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<uint> semantic_token_kinds;
RWStructuredBuffer<int> block_sum;
RWStructuredBuffer<int> block_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TK_SHR = 44u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;

groupshared int2 scan_values[256];

uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }

int token_delta(uint raw_kind, uint semantic_kind)
{
    if (semantic_kind == TK_TYPE_ARG_LT || semantic_kind == TK_GENERIC_PARAM_LT ||
        semantic_kind == TK_BOUND_TYPE_ARG_LT || semantic_kind == TK_PATH_TYPE_ARG_LT)
        return 1;
    if (semantic_kind == TK_TYPE_ARG_GT || semantic_kind == TK_GENERIC_PARAM_GT ||
        semantic_kind == TK_BOUND_TYPE_ARG_GT || semantic_kind == TK_PATH_TYPE_ARG_GT)
        return -1;
    return raw_kind == TK_SHR ? -2 : 0;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = linear_group_id(gid);
    if (block >= gParams.n_blocks)
        return;
    uint i = block * WG_SIZE + ltid.x;
    uint count = min(lexer_token_count[0], gParams.n_tokens);
    int delta = i < count ? token_delta(token_words[i].kind, semantic_token_kinds[i + 1u]) : 0;
    int2 element = int2(delta, min(0, delta));
    int2 inclusive = prefix_scan_inclusive<int2, PrefixScanI32x2SumMinPrefix, 256>(
        ltid.x, element, scan_values);
    if (ltid.x + 1u == WG_SIZE)
    {
        block_sum[block] = inclusive.x;
        block_min[block] = inclusive.y;
    }
}
