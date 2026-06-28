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
    uint uses_status_count;
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
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_type_len_token;

RWStructuredBuffer<uint> hir_expr_int_value;
RWStructuredBuffer<uint> hir_expr_float_bits;
RWStructuredBuffer<uint> hir_type_len_value;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirLiteral.uses_status_count != 0u ? min(gHirLiteral.n, tree_count_status[5u]) : gHirLiteral.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gHirLiteral.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

void consume_decimal_digit(uint start, uint len, uint i, inout uint value, inout bool active)
{
    if (!active || i >= len)
    {
        active = false;
        return;
    }
    uint ch = source_at(start, i);
    if (ch < 48u || ch > 57u)
    {
        active = false;
        return;
    }
    value = value * 10u + (ch - 48u);
}

uint parse_uint_token(uint token_i)
{
    uint value = 0u;
    uint start = token_words[token_i].start;
    uint len = token_words[token_i].len;
    bool active = true;
    consume_decimal_digit(start, len, 0u, value, active);
    consume_decimal_digit(start, len, 1u, value, active);
    consume_decimal_digit(start, len, 2u, value, active);
    consume_decimal_digit(start, len, 3u, value, active);
    consume_decimal_digit(start, len, 4u, value, active);
    consume_decimal_digit(start, len, 5u, value, active);
    consume_decimal_digit(start, len, 6u, value, active);
    consume_decimal_digit(start, len, 7u, value, active);
    consume_decimal_digit(start, len, 8u, value, active);
    consume_decimal_digit(start, len, 9u, value, active);
    return value;
}

uint parse_float_token_bits(uint token_i)
{
    uint start = token_words[token_i].start;
    uint len = token_words[token_i].len;
    float value = 0.0;
    float frac_scale = 0.1;
    uint exponent = 0u;
    bool after_dot = false;
    bool after_exp = false;
    bool exp_negative = false;
    bool exp_sign_allowed = false;

    for (uint i = 0u; i < len && i < 64u; i += 1u)
    {
        uint ch = source_at(start, i);
        if (ch == 95u)
            continue;
        if (!after_exp && ch == 46u)
        {
            after_dot = true;
            continue;
        }
        if (!after_exp && (ch == 101u || ch == 69u))
        {
            after_exp = true;
            exp_sign_allowed = true;
            continue;
        }
        if (exp_sign_allowed && (ch == 43u || ch == 45u))
        {
            exp_negative = ch == 45u;
            exp_sign_allowed = false;
            continue;
        }
        exp_sign_allowed = false;
        if (ch < 48u || ch > 57u)
            break;

        uint digit = ch - 48u;
        if (after_exp)
        {
            exponent = exponent * 10u + digit;
        }
        else if (after_dot)
        {
            value += float(digit) * frac_scale;
            frac_scale *= 0.1;
        }
        else
        {
            value = value * 10.0 + float(digit);
        }
    }

    float scale = 1.0;
    uint capped_exponent = min(exponent, 38u);
    for (uint e = 0u; e < capped_exponent; e += 1u)
        scale *= 10.0;
    if (after_exp)
        value = exp_negative ? value / scale : value * scale;

    return asuint(value);
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
    hir_expr_float_bits[i] = 0u;
    hir_type_len_value[i] = INVALID;

    if (!valid_node(i))
        return;

    uint len_token = hir_type_len_token[i];
    if (token_starts_with_digit(len_token))
        hir_type_len_value[i] = parse_uint_token(len_token);

    if (expr_slot(i, HIR_EXPR_RECORD_FORM) != HIR_EXPR_INT)
    {
        if (expr_slot(i, HIR_EXPR_RECORD_FORM) != HIR_EXPR_FLOAT)
            return;

        uint value_token = expr_slot(i, HIR_EXPR_RECORD_VALUE_TOKEN);
        if (value_token == INVALID)
            return;

        hir_expr_float_bits[i] = parse_float_token_bits(value_token);
        return;
    }

    uint value_token = expr_slot(i, HIR_EXPR_RECORD_VALUE_TOKEN);
    if (value_token == INVALID)
        return;

    hir_expr_int_value[i] = parse_uint_token(value_token);
}
