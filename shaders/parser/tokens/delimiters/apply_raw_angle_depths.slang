// Materialize global clamped raw-angle depth before every token. Existing
// parser-context consumers can keep their additive depth interface by reading
// these global values with a zero block prefix.

import prefix_scan;

struct Params { uint n_tokens; uint n_blocks; uint scan_step; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<int> block_prefix_sum;
StructuredBuffer<int> block_prefix_min;
RWStructuredBuffer<int> depth_angle_inblock;
RWStructuredBuffer<int> block_prefix_angle;
RWStructuredBuffer<int> block_sum_angle;

static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_SHR = 44u;
groupshared int2 scan_values[256];

int raw_delta(uint kind)
{
    if (kind == TK_LT) return 1;
    if (kind == TK_GT) return -1;
    if (kind == TK_SHR) return -2;
    return 0;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint i = tid.x;
    uint count = min(lexer_token_count[0], gParams.n_tokens);
    int delta = i < count ? raw_delta(token_words[i].kind) : 0;
    int2 inclusive = prefix_scan_inclusive<int2, PrefixScanI32x2SumMinPrefix, 256>(
        ltid.x, int2(delta, min(0, delta)), scan_values);
    int2 exclusive = ltid.x == 0u ? int2(0, 0) : scan_values[ltid.x - 1u];
    GroupMemoryBarrierWithGroupSync();
    uint block = i / 256u;
    if (i < gParams.n_tokens)
    {
        int prior_sum = block_prefix_sum[block];
        int sum_before = prior_sum + exclusive.x;
        int min_before = min(block_prefix_min[block], prior_sum + exclusive.y);
        depth_angle_inblock[i] = sum_before - min(0, min_before);
    }
    if (ltid.x == 0u && block < gParams.n_blocks)
    {
        block_prefix_angle[block] = 0;
        block_sum_angle[block] = 0;
    }
}
