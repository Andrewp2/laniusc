// Paper-aligned name extraction foundation.
//
// GPU-only scheduling contract:
// - This pass marks lexer-produced name-bearing tokens only. It does not resolve
//   declarations, imports, modules, or paths.
// - The mark output is prefix-scanned on the GPU. The host schedules the scan
//   and later scatter/radix passes, but does not inspect name bytes.

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

RWStructuredBuffer<uint> name_lexeme_flag;
RWStructuredBuffer<uint> name_lexeme_kind;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint NAME_KIND_NONE = 0u;
static const uint NAME_KIND_IDENTIFIER = 1u;
static const uint NAME_KIND_STRING = 2u;

static const uint TK_IDENT = 1u;
static const uint TK_STRING = 32u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint token_kind(uint i)
{
    return i < active_token_count() ? token_words[i].kind : 0u;
}

uint name_kind_for_token(uint kind)
{
    if (kind == TK_IDENT || kind == TK_LET_IDENT || kind == TK_PARAM_IDENT || kind == TK_TYPE_IDENT)
        return NAME_KIND_IDENTIFIER;
    if (kind == TK_STRING)
        return NAME_KIND_STRING;
    return NAME_KIND_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    uint kind = i < active_token_count() ? name_kind_for_token(token_kind(i)) : NAME_KIND_NONE;
    name_lexeme_kind[i] = kind;
    name_lexeme_flag[i] = kind == NAME_KIND_NONE ? 0u : 1u;
}
