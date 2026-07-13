// Raw-angle stack effects used before semantic token classification. This is
// deliberately context-free: semantic refinement later decides whether a raw
// `>>` is generic, while this phase prevents it from poisoning all following
// token contexts.

import prefix_scan;

struct Params { uint n_tokens; uint n_blocks; uint scan_step; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
RWStructuredBuffer<int> block_sum;
RWStructuredBuffer<int> block_min;

static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_SHR = 44u;
static const uint MAX_GROUPS_X = 65535u;
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
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    if (block >= gParams.n_blocks) return;
    uint i = block * 256u + ltid.x;
    uint count = min(lexer_token_count[0], gParams.n_tokens);
    int delta = i < count ? raw_delta(token_words[i].kind) : 0;
    int2 summary = prefix_scan_inclusive<int2, PrefixScanI32x2SumMinPrefix, 256>(
        ltid.x, int2(delta, min(0, delta)), scan_values);
    if (ltid.x == 255u)
    {
        block_sum[block] = summary.x;
        block_min[block] = summary.y;
    }
}
