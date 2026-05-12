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

StructuredBuffer<uint> method_decl_receiver_type;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_lookup_key;
StructuredBuffer<uint> method_lookup_receiver;
StructuredBuffer<uint> method_lookup_name_token;
StructuredBuffer<uint> method_lookup_fn;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_FLOAT = 33u;
static const uint TK_STRING = 32u;
static const uint TK_CHAR = 34u;
static const uint TK_DOT = 35u;
static const uint TK_COMMA = 36u;
static const uint TK_COLON = 38u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_SELF_VALUE = 105u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 16u;
static const uint MAX_METHOD_LOOKUP_PROBE = 32u;

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

uint method_key(uint receiver_ty, uint name_i)
{
    return (receiver_ty * 16777619u) ^ token_hash(name_i);
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_GROUP_RPAREN || kind == TK_RPAREN || kind == TK_CALL_RPAREN;
}

uint find_call_close(uint call_lparen_i)
{
    uint n_active = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = call_lparen_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            depth += 1u;
        else if (is_group_close_kind(kind))
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
    }
    return INVALID;
}

uint call_arg_count(uint call_lparen_i, uint close_i)
{
    if (close_i == INVALID || call_lparen_i + 1u >= close_i)
        return 0u;

    uint group_depth = 0u;
    uint count = 1u;
    [loop]
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u)
            count += 1u;
    }
    return count;
}

uint call_arg_start(uint call_lparen_i, uint close_i, uint arg_index)
{
    uint current = 0u;
    uint start = call_lparen_i + 1u;
    uint group_depth = 0u;
    [loop]
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u)
        {
            if (current == arg_index)
                return start < j ? start : INVALID;
            current += 1u;
            start = j + 1u;
        }
    }
    if (current == arg_index)
        return start < close_i ? start : INVALID;
    return INVALID;
}

uint call_arg_end(uint arg_start_i, uint close_i)
{
    uint group_depth = 0u;
    [loop]
    for (uint j = arg_start_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u)
            return j;
    }
    return close_i;
}

uint leading_expr_token(uint start_i, uint end_i)
{
    uint cur = start_i;
    [loop]
    for (uint guard = 0u; guard < 16u && cur < end_i && cur < active_token_count();
         guard += 1u)
    {
        if (token_kind(cur) == TK_GROUP_LPAREN || token_kind(cur) == TK_LPAREN)
        {
            cur += 1u;
            continue;
        }
        break;
    }
    return cur;
}

uint simple_arg_type(uint start_i, uint end_i)
{
    uint cur = leading_expr_token(start_i, end_i);
    uint kind = token_kind(cur);
    if (kind == TK_INT)
        return TY_INT;
    if (kind == TK_TRUE || kind == TK_FALSE)
        return TY_BOOL;
    if (kind == TK_FLOAT)
        return TY_FLOAT;
    if (kind == TK_STRING)
        return TY_STRING;
    if (kind == TK_CHAR)
        return TY_CHAR;
    if (kind == TK_IDENT || kind == TK_SELF_VALUE)
    {
        if (cur + 2u < end_i && token_kind(cur + 1u) == TK_DOT &&
            token_kind(cur + 2u) == TK_IDENT && visible_type[cur + 2u] != TY_UNKNOWN)
            return visible_type[cur + 2u];
        if (cur + 1u < end_i &&
            (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN))
            return call_return_type[cur];
        return visible_type[cur];
    }
    return TY_UNKNOWN;
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return true;
    if (dst == src)
        return true;
    if (dst == TY_INT)
        return src == TY_UINT || src == TY_CHAR;
    if (dst == TY_UINT)
        return src == TY_INT || src == TY_CHAR;
    if (dst == TY_FLOAT)
        return src == TY_INT || src == TY_UINT || src == TY_CHAR;
    return false;
}

uint lookup_method(uint receiver_ty, uint name_i)
{
    if (receiver_ty == TY_UNKNOWN)
        return INVALID;

    uint cap = lookup_capacity();
    uint key = method_key(receiver_ty, name_i);
    uint start_slot = key % cap;
    uint probe_limit = min(cap, MAX_METHOD_LOOKUP_PROBE);
    [loop]
    for (uint probe = 0u; probe < probe_limit; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint fn_i = method_lookup_fn[slot];
        if (fn_i == INVALID)
            return INVALID;
        if (method_lookup_key[slot] == key && method_lookup_receiver[slot] == receiver_ty &&
            same_text(method_lookup_name_token[slot], name_i))
            return fn_i;
    }
    return INVALID;
}

bool method_has_self_receiver(uint fn_i)
{
    uint first = method_decl_param_offset[fn_i];
    if (first == INVALID || first >= active_token_count())
        return false;
    return token_kind(first) == TK_SELF_VALUE ||
           (token_kind(first) == TK_AMPERSAND && first + 1u < active_token_count() &&
            token_kind(first + 1u) == TK_SELF_VALUE);
}

bool method_explicit_receiver_consumes_param(uint fn_i, uint receiver_ty)
{
    if (method_has_self_receiver(fn_i))
        return false;
    uint first = method_decl_param_offset[fn_i];
    if (first == INVALID || first + 2u >= active_token_count())
        return false;
    uint kind = token_kind(first);
    if ((kind != TK_IDENT && kind != TK_PARAM_IDENT) || token_kind(first + 1u) != TK_COLON)
        return false;
    if (call_param_count[fn_i] == 0u)
        return false;
    uint first_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE];
    return first_ty == receiver_ty;
}

bool validate_method_args(uint method_i, uint open_i, uint close_i, uint fn_i, uint receiver_ty)
{
    uint param_count = call_param_count[fn_i];
    bool has_self_receiver = method_has_self_receiver(fn_i);
    bool consumes_receiver = method_explicit_receiver_consumes_param(fn_i, receiver_ty);
    if (!has_self_receiver && !consumes_receiver)
    {
        record_error(method_i, ERR_CALL_MISMATCH, receiver_ty);
        return false;
    }
    uint expected_args = consumes_receiver && param_count > 0u ? param_count - 1u : param_count;
    uint actual_args = call_arg_count(open_i, close_i);
    if (actual_args != expected_args)
    {
        record_error(method_i, ERR_CALL_MISMATCH, expected_args * 256u + actual_args);
        return false;
    }

    [loop]
    for (uint arg_i = 0u; arg_i < actual_args && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_i = consumes_receiver ? arg_i + 1u : arg_i;
        if (param_i >= PARAM_CACHE_STRIDE)
            return false;
        uint dst = call_param_type[fn_i * PARAM_CACHE_STRIDE + param_i];
        uint arg_start_i = call_arg_start(open_i, close_i, arg_i);
        if (arg_start_i == INVALID)
            return false;
        uint arg_end_i = call_arg_end(arg_start_i, close_i);
        uint src = simple_arg_type(arg_start_i, arg_end_i);
        if (!assignable(dst, src))
        {
            record_error(arg_start_i, ERR_ASSIGN_MISMATCH, dst * 256u + src);
            return false;
        }
    }
    return true;
}

void resolve_method_call(uint method_i)
{
    if (method_i < 2u || method_i + 1u >= active_token_count())
        return;
    if (token_kind(method_i) != TK_IDENT || token_kind(method_i - 1u) != TK_DOT ||
        (token_kind(method_i + 1u) != TK_CALL_LPAREN && token_kind(method_i + 1u) != TK_LPAREN))
        return;

    uint receiver_i = method_i - 2u;
    uint receiver_kind = token_kind(receiver_i);
    if (receiver_kind != TK_IDENT && receiver_kind != TK_SELF_VALUE)
        return;

    uint receiver_ty = visible_type[receiver_i];
    uint fn_i = lookup_method(receiver_ty, method_i);
    if (fn_i == INVALID)
        return;
    if (method_decl_receiver_type[fn_i] != receiver_ty)
        return;

    uint ret_ty = call_return_type[fn_i];
    call_fn_index[method_i] = fn_i;
    call_return_type[method_i] = ret_ty;
    call_return_type_token[method_i] = call_return_type_token[fn_i];
    if (ret_ty != TY_UNKNOWN)
        visible_type[method_i] = ret_ty;

    uint close_i = find_call_close(method_i + 1u);
    if (close_i != INVALID)
        validate_method_args(method_i, method_i + 1u, close_i, fn_i, receiver_ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    resolve_method_call(i);
}
