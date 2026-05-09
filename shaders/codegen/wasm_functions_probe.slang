import utils;

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
ByteAddressBuffer source_bytes;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> dispatch_args;

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_FN = 67u;
static const uint FUNCTION_MODULE_NEEDED = 4u;
static const uint SIMPLE_FAST_PATH_DONE = 2u;
static const uint MAX_DISPATCH_X = 65535u;
static const uint INVALID = 0xffffffffu;

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint token_kind(uint i)
{
    return i < active_token_count() ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    return i < active_token_count() ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    return i < active_token_count() ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

bool span5(uint start, uint len, uint a, uint b, uint c, uint d, uint e)
{
    return len == 5u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d &&
           source_at(start, 4u) == e;
}

bool is_print_name(uint i)
{
    return span5(token_start(i), token_len(i), 112u, 114u, 105u, 110u, 116u);
}

bool is_assert_name(uint i)
{
    uint start = token_start(i);
    return token_len(i) == 6u && source_at(start, 0u) == 97u &&
           source_at(start, 1u) == 115u && source_at(start, 2u) == 115u &&
           source_at(start, 3u) == 101u && source_at(start, 4u) == 114u &&
           source_at(start, 5u) == 116u;
}

bool is_builtin_name(uint i)
{
    return is_print_name(i) || is_assert_name(i);
}

bool same_text(uint a_i, uint b_i)
{
    uint len = token_len(a_i);
    if (len != token_len(b_i))
        return false;
    uint a = token_start(a_i);
    uint b = token_start(b_i);
    [loop]
    for (uint i = 0u; i < len && i < 64u; i += 1u)
    {
        if (source_at(a, i) != source_at(b, i))
            return false;
    }
    return true;
}

uint find_named_function(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i + 1u < n; i += 1u)
    {
        if (token_kind(i) == TK_FN && same_text(i + 1u, name_i))
            return i;
    }
    return INVALID;
}

bool token_needs_function_module(uint i)
{
    return token_kind(i) == TK_IDENT &&
           (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN) &&
           (i == 0u || token_kind(i - 1u) != TK_FN) &&
           !is_builtin_name(i) && find_named_function(i) != INVALID;
}

void enable_function_dispatch()
{
    uint groups = (gParams.out_capacity + 255u) / 256u;
    dispatch_args[0u] = min(groups, MAX_DISPATCH_X);
    dispatch_args[1u] = (groups + MAX_DISPATCH_X - 1u) / MAX_DISPATCH_X;
    dispatch_args[2u] = 1u;
    InterlockedOr(status[1u], FUNCTION_MODULE_NEEDED);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[1u] == SIMPLE_FAST_PATH_DONE)
        return;

    uint i = tid.x;
    if (i + 1u >= active_token_count())
        return;

    if (token_needs_function_module(i))
        enable_function_dispatch();
}
