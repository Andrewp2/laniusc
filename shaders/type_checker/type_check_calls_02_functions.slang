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
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_ARRAY_BASE = 128u;

static const uint TK_IDENT = 1u;
static const uint TK_RPAREN = 5u;
static const uint TK_LBRACKET = 20u;
static const uint TK_LBRACE = 22u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_COLON = 38u;
static const uint TK_ARROW = 75u;
static const uint TK_FN = 67u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_IF_LBRACE = 88u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 16u;

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

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

bool span2(uint start, uint len, uint a, uint b)
{
    return len == 2u && source_at(start, 0u) == a && source_at(start, 1u) == b;
}

bool span3(uint start, uint len, uint a, uint b, uint c)
{
    return len == 3u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c;
}

bool span4(uint start, uint len, uint a, uint b, uint c, uint d)
{
    return len == 4u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d;
}

bool span5(uint start, uint len, uint a, uint b, uint c, uint d, uint e)
{
    return len == 5u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d &&
           source_at(start, 4u) == e;
}

bool token_text_eq(uint i, uint a, uint b, uint c, uint d)
{
    return span4(token_start(i), token_len(i), a, b, c, d);
}

bool same_text(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;
    uint sa = token_start(a);
    uint sb = token_start(b);
    [loop]
    for (uint i = 0u; i < len; i += 1u)
    {
        if (source_at(sa, i) != source_at(sb, i))
            return false;
    }
    return true;
}

uint token_hash(uint i)
{
    uint h = 2166136261u;
    uint start = token_start(i);
    uint len = token_len(i);
    [loop]
    for (uint d = 0u; d < len; d += 1u)
    {
        h = (h ^ source_at(start, d)) * 16777619u;
    }
    return h ^ len;
}

uint primitive_type_code(uint type_i)
{
    uint start = token_start(type_i);
    uint len = token_len(type_i);
    if (span2(start, len, 105u, 56u) || span3(start, len, 105u, 49u, 54u) ||
        span3(start, len, 105u, 51u, 50u) || span3(start, len, 105u, 54u, 52u) ||
        span5(start, len, 105u, 115u, 105u, 122u, 101u))
        return TY_INT;

    if (span2(start, len, 117u, 56u) || span3(start, len, 117u, 49u, 54u) ||
        span3(start, len, 117u, 51u, 50u) || span3(start, len, 117u, 54u, 52u) ||
        span5(start, len, 117u, 115u, 105u, 122u, 101u))
        return TY_UINT;

    if (span3(start, len, 102u, 51u, 50u) || span3(start, len, 102u, 54u, 52u))
        return TY_FLOAT;
    if (span4(start, len, 98u, 111u, 111u, 108u))
        return 2u;
    if (span4(start, len, 99u, 104u, 97u, 114u))
        return TY_CHAR;

    return TY_UNKNOWN;
}

uint type_code_for_type_expr(uint type_i)
{
    uint cur = type_i;
    uint array_depth = 0u;
    uint n_active = active_token_count();
    [loop]
    for (uint guard = 0u; guard < 16u && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind != TK_TYPE_ARRAY_LBRACKET && kind != TK_ARRAY_LBRACKET && kind != TK_LBRACKET)
            break;
        array_depth += 1u;
        cur += 1u;
    }

    uint kind = token_kind(cur);
    uint elem = TY_UNKNOWN;
    if (kind == TK_TYPE_IDENT || kind == TK_IDENT)
        elem = primitive_type_code(cur);

    if (elem == TY_UNKNOWN)
        return TY_UNKNOWN;
    return array_depth == 0u ? elem : TY_ARRAY_BASE + elem;
}

uint function_return_type_from_token(uint fn_i, uint ret_i)
{
    if (ret_i != INVALID)
        return type_code_for_type_expr(ret_i);
    if (fn_i + 1u < active_token_count() && token_text_eq(fn_i + 1u, 109u, 97u, 105u, 110u))
        return TY_INT;
    return TY_VOID;
}

uint function_return_type_token(uint fn_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = fn_i + 2u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE)
            return INVALID;
        if (kind == TK_ARROW)
            return j + 1u;
    }
    return INVALID;
}

bool is_param_decl(uint i)
{
    uint n_active = active_token_count();
    uint kind = token_kind(i);
    return kind == TK_PARAM_IDENT ||
           (kind == TK_IDENT && i + 1u < n_active && token_kind(i + 1u) == TK_COLON);
}

void cache_function_params(uint fn_i)
{
    uint count = 0u;
    uint n_active = active_token_count();
    [loop]
    for (uint j = fn_i + 2u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_PARAM_RPAREN || kind == TK_RPAREN || kind == TK_LBRACE || kind == TK_IF_LBRACE)
            break;
        if (!is_param_decl(j))
            continue;
        if (count < PARAM_CACHE_STRIDE)
            call_param_type[fn_i * PARAM_CACHE_STRIDE + count] = type_code_for_type_expr(j + 2u);
        count += 1u;
    }
    call_param_count[fn_i] = count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count() || token_kind(i) != TK_FN)
        return;

    call_fn_index[i] = i;
    uint ret_i = function_return_type_token(i);
    call_return_type_token[i] = ret_i;
    call_return_type[i] = function_return_type_from_token(i, ret_i);
    cache_function_params(i);

    uint cap = lookup_capacity();
    uint key = token_hash(i + 1u);
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint old_fn;
        InterlockedCompareExchange(function_lookup_fn[slot], INVALID, i, old_fn);
        if (old_fn == INVALID)
        {
            function_lookup_key[slot] = key;
            return;
        }
        if (function_lookup_key[slot] == key && same_text(old_fn + 1u, i + 1u))
        {
            uint old_min;
            InterlockedMin(function_lookup_fn[slot], i, old_min);
            return;
        }
    }
}
