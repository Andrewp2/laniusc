struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint segment_count;
    uint segment_len;
    uint block_count;
    uint scan_step;
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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;

RWStructuredBuffer<uint> token_hir_role;
RWStructuredBuffer<int> token_function_delta;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint TK_PUB = 66u;
static const uint HIR_ROLE_SHIFT = 24u;
static const uint HIR_ROLE_END_MASK = 0x00ffffffu;

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= active_hir_node_count())
        return;

    uint pos = hir_token_pos[i];
    if (pos == INVALID || pos >= gParams.n_tokens)
        return;

    uint kind = hir_kind[i];
    uint end = hir_token_end[i];
    if (end == INVALID)
        end = pos + 1u;
    end = min(end, gParams.n_tokens);
    end = min(end, HIR_ROLE_END_MASK);
    uint packed = (min(kind, 255u) << HIR_ROLE_SHIFT) | end;
    uint old_value;
    InterlockedMax(token_hir_role[pos], packed, old_value);

    if (kind == HIR_FN)
    {
        uint first = pos;
        if (pos > 0u && token_words[pos - 1u].kind == TK_PUB)
            first = pos - 1u;

        int old_delta;
        InterlockedAdd(token_function_delta[first], 1, old_delta);
        if (end < gParams.n_tokens)
            InterlockedAdd(token_function_delta[end], -1, old_delta);
    }
}
