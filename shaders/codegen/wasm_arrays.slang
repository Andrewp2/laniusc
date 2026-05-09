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
RWStructuredBuffer<uint> array_len;
RWStructuredBuffer<uint> array_values;
StructuredBuffer<uint> body_status;

static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_LET = 68u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint MAX_ARRAY_ELEMS = 16u;

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

uint parse_uint_token(uint token_i)
{
    uint value = 0u;
    uint start = token_start(token_i);
    uint len = token_len(token_i);
    [loop]
    for (uint i = 0u; i < len && i < 10u; i += 1u)
    {
        uint ch = source_at(start, i);
        if (ch < 48u || ch > 57u)
            break;
        value = value * 10u + (ch - 48u);
    }
    return value;
}

bool is_array_open(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET;
}

bool is_array_close(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET;
}

bool is_open_paren(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_close_paren(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN;
}

uint statement_end(uint start_i)
{
    uint n = active_token_count();
    uint paren_depth = 0u;
    uint bracket_depth = 0u;
    [loop]
    for (uint i = start_i; i < n; i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_paren(kind))
            paren_depth += 1u;
        else if (is_close_paren(kind) && paren_depth > 0u)
            paren_depth -= 1u;
        else if (is_array_open(kind))
            bracket_depth += 1u;
        else if (is_array_close(kind) && bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (kind == TK_SEMICOLON && paren_depth == 0u && bracket_depth == 0u)
            return i;
    }
    return n;
}

uint find_assign(uint start_i, uint end_i)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
            return i;
    }
    return 0xffffffffu;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (body_status[1u] == 2u)
        return;

    uint i = tid.x;
    uint n = active_token_count();
    if (i + 1u >= n || token_kind(i) != TK_LET)
        return;

    uint decl = i + 1u;
    array_len[decl] = 0u;
    uint semi = statement_end(i);
    uint assign_i = find_assign(i, semi);
    if (assign_i == 0xffffffffu || assign_i + 1u >= semi ||
        !is_array_open(token_kind(assign_i + 1u)))
        return;

    uint elem_start = assign_i + 2u;
    uint elem_index = 0u;
    [loop]
    for (uint j = elem_start; j < semi && j < n && elem_index < MAX_ARRAY_ELEMS; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_ARRAY_COMMA || kind == TK_COMMA || is_array_close(kind))
        {
            [loop]
            for (uint k = elem_start; k < j && k < n; k += 1u)
            {
                if (token_kind(k) == TK_INT)
                {
                    array_values[decl * MAX_ARRAY_ELEMS + elem_index] = parse_uint_token(k);
                    elem_index += 1u;
                    break;
                }
            }
            elem_start = j + 1u;
            if (is_array_close(kind))
                break;
        }
    }
    array_len[decl] = elem_index;
}
