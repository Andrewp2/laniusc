// Extract literal payload metadata for expression HIR nodes.
//
// Expression shape stays in hir_expr_fields, which is derived from production
// ids and inverted tree links. This pass performs the separate source-byte
// value extraction for literal leaves and publishes a GPU-owned value buffer so
// backend passes do not parse source text.

import utils;

struct Params
{
    uint n;
    uint source_len;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirLiteral;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
ByteAddressBuffer source_bytes;
StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_expr_form;
StructuredBuffer<uint> hir_expr_value_token;
StructuredBuffer<uint> hir_type_len_token;

RWStructuredBuffer<uint> hir_expr_int_value;
RWStructuredBuffer<uint> hir_type_len_value;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR_INT = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirLiteral.uses_ll1 != 0u ? min(gHirLiteral.n, ll1_status[5u]) : gHirLiteral.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gHirLiteral.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

uint parse_uint_token(uint token_i)
{
    uint value = 0u;
    uint start = token_words[token_i].start;
    uint len = token_words[token_i].len;
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

bool token_starts_with_digit(uint token_i)
{
    if (token_i == INVALID)
        return false;
    uint len = token_words[token_i].len;
    if (len == 0u)
        return false;
    uint ch = source_at(token_words[token_i].start, 0u);
    return ch >= 48u && ch <= 57u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirLiteral.n)
        return;

    hir_expr_int_value[i] = 0u;
    hir_type_len_value[i] = INVALID;

    if (!valid_node(i))
        return;

    uint len_token = hir_type_len_token[i];
    if (token_starts_with_digit(len_token))
        hir_type_len_value[i] = parse_uint_token(len_token);

    if (hir_expr_form[i] != HIR_EXPR_INT)
        return;

    uint value_token = hir_expr_value_token[i];
    if (value_token == INVALID)
        return;

    hir_expr_int_value[i] = parse_uint_token(value_token);
}
