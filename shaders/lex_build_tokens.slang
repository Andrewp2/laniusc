// shaders/lex_build_tokens.slang
// Stage 5: turn compacted ends into (start,len,kind)

StructuredBuffer<uint> token_count;   // total tokens
StructuredBuffer<uint> end_positions; // compacted exclusive ends
StructuredBuffer<uint> types_compact; // compacted kinds

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};
RWStructuredBuffer<TokenOut> tokens_out;

[shader("compute")]
[numthreads(128, 1, 1)]
void build_tokens(uint3 tid: SV_DispatchThreadID)
{
    uint k = tid.x;
    uint total = token_count[0];
    if (k >= total)
        return;

    uint start = (k == 0u) ? 0u : end_positions[k - 1u];
    uint end = end_positions[k];
    uint len = end - start;

    TokenOut t;
    t.kind = types_compact[k];
    t.start = start;
    t.len = len;
    tokens_out[k] = t;
}
