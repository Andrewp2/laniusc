struct Params
{
    uint token_capacity;
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

RWStructuredBuffer<uint> token_kinds;
RWStructuredBuffer<uint> parser_token_count;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    uint count = min(lexer_token_count[0], gParams.token_capacity);
    uint out_count = count + 2u;
    if (i >= out_count)
        return;

    if (i == 0u || i == count + 1u)
    {
        token_kinds[i] = 0u;
    }
    else
    {
        token_kinds[i] = token_words[i - 1u].kind;
    }

    if (i == 0u)
        parser_token_count[0] = count;
}
