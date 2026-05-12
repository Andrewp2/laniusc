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

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_elem_ref_tag;
RWStructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> fn_return_ref_tag;
RWStructuredBuffer<uint> fn_return_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TYPE_INSTANCE_INVALID = 0u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;

static const uint TYPE_INSTANCE_EMPTY = 0u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNRESOLVED = 2u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;

static const uint TYPE_LEN_NONE = 0u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint TYPE_LEN_UNSUPPORTED = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_ARROW = 75u;
static const uint TK_FN = 67u;
static const uint TK_LBRACE = 22u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_TYPE_SCAN = 64u;

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

bool is_type_array_open(uint kind)
{
    return kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

bool is_type_array_close(uint kind)
{
    return kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_RBRACKET;
}

bool is_type_array_semicolon(uint kind)
{
    return kind == TK_TYPE_SEMICOLON || kind == TK_SEMICOLON;
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
        return TY_BOOL;
    if (span4(start, len, 99u, 104u, 97u, 114u))
        return TY_CHAR;
    if (span3(start, len, 115u, 116u, 114u))
        return TY_STRING;

    return TY_UNKNOWN;
}

uint parse_uint_token(uint i)
{
    uint start = token_start(i);
    uint len = token_len(i);
    if (len == 0u)
        return INVALID;

    uint value = 0u;
    for (uint d = 0u; d < len; d += 1u)
    {
        uint ch = source_at(start, d);
        if (ch < 48u || ch > 57u)
            return INVALID;
        value = value * 10u + (ch - 48u);
    }
    return value;
}

void clear_slot(uint i)
{
    type_expr_ref_tag[i] = TYPE_REF_INVALID;
    type_expr_ref_payload[i] = INVALID;
    type_instance_kind[i] = TYPE_INSTANCE_INVALID;
    type_instance_head_token[i] = INVALID;
    type_instance_arg_start[i] = INVALID;
    type_instance_arg_count[i] = 0u;
    type_instance_elem_ref_tag[i] = TYPE_REF_INVALID;
    type_instance_elem_ref_payload[i] = INVALID;
    type_instance_len_kind[i] = TYPE_LEN_NONE;
    type_instance_len_payload[i] = INVALID;
    type_instance_state[i] = TYPE_INSTANCE_EMPTY;
    fn_return_ref_tag[i] = TYPE_REF_INVALID;
    fn_return_ref_payload[i] = INVALID;
}

uint find_matching_type_array_rbracket(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    uint limit = min(n, open_i + MAX_TYPE_SCAN);
    for (uint j = open_i; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_type_array_open(kind))
            depth += 1u;
        else if (is_type_array_close(kind))
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

uint find_type_array_semicolon(uint open_i, uint close_i)
{
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        if (is_type_array_semicolon(token_kind(j)))
            return j;
    }
    return INVALID;
}

uint find_matching_gt(uint lt_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    uint limit = min(n, lt_i + MAX_TYPE_SCAN);
    for (uint j = lt_i; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            depth += 1u;
        else if (kind == TK_GT)
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

uint count_type_args(uint lt_i, uint gt_i)
{
    if (gt_i <= lt_i + 1u)
        return 0u;

    uint count = 1u;
    uint nested_angle = 0u;
    uint nested_array = 0u;
    for (uint j = lt_i + 1u; j < gt_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            nested_angle += 1u;
        else if (kind == TK_GT && nested_angle > 0u)
            nested_angle -= 1u;
        else if (is_type_array_open(kind))
            nested_array += 1u;
        else if (is_type_array_close(kind) && nested_array > 0u)
            nested_array -= 1u;
        else if (kind == TK_COMMA && nested_angle == 0u && nested_array == 0u)
            count += 1u;
    }
    return count;
}

void write_ref_for_type_head(uint out_token, uint type_head)
{
    uint primitive = primitive_type_code(type_head);
    if (primitive != TY_UNKNOWN)
    {
        type_expr_ref_tag[out_token] = TYPE_REF_SCALAR;
        type_expr_ref_payload[out_token] = primitive;
    }
    else if (token_kind(type_head) == TK_IDENT || token_kind(type_head) == TK_TYPE_IDENT)
    {
        type_expr_ref_tag[out_token] = TYPE_REF_GENERIC_PARAM;
        type_expr_ref_payload[out_token] = type_head;
    }
    else
    {
        type_expr_ref_tag[out_token] = TYPE_REF_ERROR;
        type_expr_ref_payload[out_token] = type_head;
    }
}

void collect_named_instance(uint i)
{
    if ((token_kind(i) != TK_TYPE_IDENT && token_kind(i) != TK_IDENT) ||
        token_kind(i + 1u) != TK_LT)
        return;

    uint gt_i = find_matching_gt(i + 1u);

    type_expr_ref_tag[i] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[i] = i;
    type_instance_kind[i] = TYPE_INSTANCE_NAMED;
    type_instance_head_token[i] = i;
    type_instance_arg_start[i] = i + 2u;
    type_instance_arg_count[i] = gt_i == INVALID ? 0u : count_type_args(i + 1u, gt_i);
    type_instance_state[i] = gt_i == INVALID ? TYPE_INSTANCE_UNSUPPORTED : TYPE_INSTANCE_UNRESOLVED;
}

void collect_array_or_slice_instance(uint i)
{
    if (!is_type_array_open(token_kind(i)))
        return;

    uint close_i = find_matching_type_array_rbracket(i);
    if (close_i == INVALID)
    {
        type_expr_ref_tag[i] = TYPE_REF_ERROR;
        type_expr_ref_payload[i] = i;
        type_instance_state[i] = TYPE_INSTANCE_UNSUPPORTED;
        return;
    }

    uint semicolon_i = find_type_array_semicolon(i, close_i);
    uint elem_i = i + 1u;

    type_expr_ref_tag[i] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[i] = i;
    type_instance_kind[i] = semicolon_i == INVALID ? TYPE_INSTANCE_SLICE : TYPE_INSTANCE_ARRAY;
    type_instance_head_token[i] = i;
    type_instance_state[i] = TYPE_INSTANCE_RESOLVED;

    uint primitive = primitive_type_code(elem_i);
    if (primitive != TY_UNKNOWN)
    {
        type_instance_elem_ref_tag[i] = TYPE_REF_SCALAR;
        type_instance_elem_ref_payload[i] = primitive;
    }
    else if (token_kind(elem_i) == TK_IDENT || token_kind(elem_i) == TK_TYPE_IDENT)
    {
        type_instance_elem_ref_tag[i] = TYPE_REF_GENERIC_PARAM;
        type_instance_elem_ref_payload[i] = elem_i;
    }
    else
    {
        type_instance_elem_ref_tag[i] = TYPE_REF_ERROR;
        type_instance_elem_ref_payload[i] = elem_i;
        type_instance_state[i] = TYPE_INSTANCE_UNSUPPORTED;
    }

    if (semicolon_i == INVALID)
        return;

    uint len_i = semicolon_i + 1u;
    if (token_kind(len_i) == TK_INT)
    {
        type_instance_len_kind[i] = TYPE_LEN_LITERAL;
        type_instance_len_payload[i] = parse_uint_token(len_i);
    }
    else if (token_kind(len_i) == TK_IDENT || token_kind(len_i) == TK_TYPE_IDENT)
    {
        type_instance_len_kind[i] = TYPE_LEN_CONST_PARAM;
        type_instance_len_payload[i] = len_i;
    }
    else
    {
        type_instance_len_kind[i] = TYPE_LEN_UNSUPPORTED;
        type_instance_len_payload[i] = len_i;
        type_instance_state[i] = TYPE_INSTANCE_UNSUPPORTED;
    }
}

void collect_function_return_ref(uint i)
{
    if (token_kind(i) != TK_FN)
        return;

    uint n = active_token_count();
    uint limit = min(n, i + MAX_TYPE_SCAN);
    for (uint j = i + 1u; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            return;
        if (kind == TK_ARROW)
        {
            uint type_head = j + 1u;
            if ((token_kind(type_head) == TK_TYPE_IDENT || token_kind(type_head) == TK_IDENT) &&
                token_kind(type_head + 1u) == TK_LT)
            {
                fn_return_ref_tag[i] = TYPE_REF_INSTANCE;
                fn_return_ref_payload[i] = type_head;
            }
            else if (is_type_array_open(token_kind(type_head)))
            {
                fn_return_ref_tag[i] = TYPE_REF_INSTANCE;
                fn_return_ref_payload[i] = type_head;
            }
            else
            {
                uint primitive = primitive_type_code(type_head);
                if (primitive != TY_UNKNOWN)
                {
                    fn_return_ref_tag[i] = TYPE_REF_SCALAR;
                    fn_return_ref_payload[i] = primitive;
                }
                else if (token_kind(type_head) == TK_IDENT || token_kind(type_head) == TK_TYPE_IDENT)
                {
                    fn_return_ref_tag[i] = TYPE_REF_GENERIC_PARAM;
                    fn_return_ref_payload[i] = type_head;
                }
                else
                {
                    fn_return_ref_tag[i] = TYPE_REF_ERROR;
                    fn_return_ref_payload[i] = type_head;
                }
            }
            return;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    clear_slot(i);
    collect_named_instance(i);
    collect_array_or_slice_instance(i);
    if (type_expr_ref_tag[i] == TYPE_REF_INVALID &&
        (token_kind(i) == TK_IDENT || token_kind(i) == TK_TYPE_IDENT))
    {
        write_ref_for_type_head(i, i);
    }
    collect_function_return_ref(i);
}
