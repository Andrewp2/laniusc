import utils;

struct Params
{
    uint n_tokens;
    uint source_len;
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
ByteAddressBuffer source_bytes;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_param_type;
RWStructuredBuffer<uint> function_lookup_key;
RWStructuredBuffer<uint> function_lookup_fn;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_ARRAY_BASE = 128u;
static const uint PARAM_CACHE_STRIDE = 16u;

static const uint TK_IDENT = 1u;
static const uint TK_LBRACKET = 20u;
static const uint TK_LBRACE = 22u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_ARROW = 75u;
static const uint TK_FN = 67u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_IF_LBRACE = 88u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < gParams.n_tokens)
    {
        call_fn_index[i] = INVALID;
        call_return_type[i] = TY_UNKNOWN;
        call_return_type_token[i] = INVALID;
        call_param_count[i] = 0u;
        [loop]
        for (uint param_i = 0u; param_i < PARAM_CACHE_STRIDE; param_i += 1u)
            call_param_type[i * PARAM_CACHE_STRIDE + param_i] = TY_UNKNOWN;
    }

    if (i < lookup_capacity())
    {
        function_lookup_key[i] = 0u;
        function_lookup_fn[i] = INVALID;
    }
}
