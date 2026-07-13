// Mark only raw `>>` tokens whose parser-semantic generic stack has two live
// openers.  Clamping through min-prefix makes an ordinary shift an underflow
// that cannot perturb generic depth later in the source.

import prefix_scan;

struct Params { uint n_tokens; uint n_blocks; uint scan_step; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<int> block_prefix_sum;
StructuredBuffer<int> block_prefix_min;
RWStructuredBuffer<uint> semantic_token_kinds_rw;

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
void main(uint3 tid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint i = tid.x;
    uint count = min(lexer_token_count[0], gParams.n_tokens);
    int delta = i < count ? token_delta(token_words[i].kind, semantic_token_kinds_rw[i + 1u]) : 0;
    int2 inclusive = prefix_scan_inclusive<int2, PrefixScanI32x2SumMinPrefix, 256>(
        ltid.x, int2(delta, min(0, delta)), scan_values);
    int2 exclusive = ltid.x == 0u ? int2(0, 0) : scan_values[ltid.x - 1u];
    GroupMemoryBarrierWithGroupSync();
    if (i >= gParams.n_tokens)
        return;
    if (i >= count || token_words[i].kind != TK_SHR)
    {
        if (i < count && token_words[i].kind == TK_SHR)
            semantic_token_kinds_rw[i + 1u] = TK_SHR;
        return;
    }
    uint block = i / 256u;
    int block_sum = block_prefix_sum[block];
    int prefix = block_sum + exclusive.x;
    int minimum = min(block_prefix_min[block], block_sum + exclusive.y);
    int clamped_depth = prefix - min(0, minimum);
    uint marker = clamped_depth >= 2 ? 0x80000000u : 0u;
    semantic_token_kinds_rw[i + 1u] = marker != 0u ? marker | TK_SHR : TK_SHR;
}
