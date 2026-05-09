struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> bool_probe_status;

static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_NOT = 19u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= active_token_count())
        return;

    uint kind = token_words[i].kind;
    if (kind == TK_ANDAND || kind == TK_OROR || kind == TK_NOT)
        InterlockedOr(bool_probe_status[1u], 1u);
}
