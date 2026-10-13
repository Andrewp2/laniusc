// Extract literal payload metadata for expression HIR nodes.
//
// Expression shape stays in hir_expr_fields, which is derived from production
// ids and inverted tree links. This pass performs the separate source-byte
// value extraction for literal leaves and publishes a GPU-owned value buffer so
// backend passes do not parse source text.

import utils;
import integer_words;
import atomics;

struct Params
{
    uint n;
    uint source_len;
    uint uses_status_count;
    uint token_capacity;
    uint retain_debug_rows;
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
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint2> hir_expr_int_value;
// Each zero-initialized slot stores ~token for its earliest rejection.
// Separate failure slots make both the token and reason deterministic.
RWStructuredBuffer<uint> hir_literal_status;
RWStructuredBuffer<uint> hir_expr_string_start;
RWStructuredBuffer<uint> hir_expr_string_len;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_CHAR = 29u;
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

void reject_integer_token(uint token, uint reason)
{
    if (token < gHirLiteral.token_capacity && reason < 3u)
        atomic_u32_max(hir_literal_status, reason, ~token);
}

bool parse_uint_token(uint token, out uint2 magnitude)
{
    magnitude = uint2(0u, 0u);
    if (token >= gHirLiteral.token_capacity) return false;
    uint start = token_words[token].start;
    uint len = token_words[token].len;
    if (len == 0u || start > gHirLiteral.source_len || len > gHirLiteral.source_len - start)
    { reject_integer_token(token, 2u); return false; }
    uint radix = 10u;
    uint first_digit = 0u;
    if (len >= 2u && load_byte_at(source_bytes, start) == 48u)
    {
        uint prefix = load_byte_at(source_bytes, start + 1u) | 32u;
        if (prefix == 120u) { radix = 16u; first_digit = 2u; }
        else if (prefix == 98u) { radix = 2u; first_digit = 2u; }
        else if (prefix == 111u) { radix = 8u; first_digit = 2u; }
    }
    uint2 value = uint2(0u, 0u);
    bool need_digit = true;
    for (uint i = first_digit; i < len; i++)
    {
        uint ch = load_byte_at(source_bytes, start + i);
        if (ch == 95u)
        {
            if (need_digit) { reject_integer_token(token, 2u); return false; }
            need_digit = true;
            continue;
        }
        uint digit = ch >= 48u && ch <= 57u ? ch - 48u :
            ch >= 65u && ch <= 70u ? ch - 65u + 10u :
            ch >= 97u && ch <= 102u ? ch - 97u + 10u : 16u;
        if (digit >= radix) { reject_integer_token(token, 2u); return false; }
        uint2 next;
        if (radix == 10u)
        {
            if (!integer_words_append_decimal(value, digit, next))
            { reject_integer_token(token, 0u); return false; }
        }
        else
        {
            uint shift = radix == 2u ? 1u : radix == 8u ? 3u : 4u;
            if ((value.y >> (32u - shift)) != 0u)
            { reject_integer_token(token, 0u); return false; }
            next = integer_words_shift_left(value, shift);
            next.x |= digit;
        }
        value = next;
        need_digit = false;
    }
    if (need_digit) { reject_integer_token(token, 2u); return false; }
    magnitude = value;
    return true;
}

uint decoded_escape_byte(uint escaped)
{
    if (escaped == 110u) return 10u;
    if (escaped == 114u) return 13u;
    if (escaped == 116u) return 9u;
    if (escaped == 48u) return 0u;
    if (escaped == 34u) return 34u;
    if (escaped == 92u) return 92u;
    return escaped;
}

uint parse_char_token(uint token_i)
{
    uint start = token_words[token_i].start;
    uint len = token_words[token_i].len;
    if (len < 3u) return 0u;
    uint first = source_at(start, 1u);
    if (first == 92u && len >= 4u)
        return decoded_escape_byte(source_at(start, 2u));
    if (first < 128u)
        return first;

    // Source text is UTF-8. A char literal holds one Unicode scalar, not the
    // first byte of its encoding. The closing quote accounts for the last byte.
    uint payload_len = len - 2u;
    if (payload_len == 2u && first >= 194u && first <= 223u)
    {
        uint second = source_at(start, 2u);
        if (second >= 128u && second <= 191u)
            return ((first & 31u) << 6u) | (second & 63u);
    }
    if (payload_len == 3u && first >= 224u && first <= 239u)
    {
        uint second = source_at(start, 2u);
        uint third = source_at(start, 3u);
        if (second >= 128u && second <= 191u &&
            third >= 128u && third <= 191u &&
            !(first == 224u && second < 160u) &&
            !(first == 237u && second > 159u))
            return ((first & 15u) << 12u) | ((second & 63u) << 6u) | (third & 63u);
    }
    if (payload_len == 4u && first >= 240u && first <= 244u)
    {
        uint second = source_at(start, 2u);
        uint third = source_at(start, 3u);
        uint fourth = source_at(start, 4u);
        if (second >= 128u && second <= 191u &&
            third >= 128u && third <= 191u &&
            fourth >= 128u && fourth <= 191u &&
            !(first == 240u && second < 144u) &&
            !(first == 244u && second > 143u))
            return ((first & 7u) << 18u) | ((second & 63u) << 12u) |
                   ((third & 63u) << 6u) | (fourth & 63u);
    }
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirLiteral.n)
        return;

    uint literal_row = gHirLiteral.retain_debug_rows != 0u ? i : hir_token_pos[i];
    if (gHirLiteral.retain_debug_rows != 0u)
    {
        hir_expr_int_value[literal_row] = uint2(0u, 0u);
        hir_expr_string_start[literal_row] = INVALID;
        hir_expr_string_len[literal_row] = 0u;
    }

    if (!valid_node(i))
        return;

    uint form = expr_slot(i, HIR_EXPR_RECORD_FORM);
    uint literal_capacity = gHirLiteral.retain_debug_rows != 0u
        ? gHirLiteral.n
        : gHirLiteral.token_capacity;
    if (literal_row == INVALID || literal_row >= literal_capacity)
        return;
    if (form == HIR_EXPR_STRING)
    {
        uint value_token = expr_slot(i, HIR_EXPR_RECORD_VALUE_TOKEN);
        if (value_token == INVALID)
            return;

        uint token_start = token_words[value_token].start;
        uint token_len = token_words[value_token].len;
        if (token_len >= 2u)
        {
            hir_expr_string_start[literal_row] = token_start + 1u;
            hir_expr_string_len[literal_row] = token_len - 2u;
        }
        return;
    }

    if (form == HIR_EXPR_CHAR)
    {
        uint value_token = expr_slot(i, HIR_EXPR_RECORD_VALUE_TOKEN);
        if (value_token != INVALID)
            hir_expr_int_value[literal_row] = uint2(parse_char_token(value_token), 0u);
        return;
    }

    if (form != HIR_EXPR_INT) return;

    uint value_token = expr_slot(i, HIR_EXPR_RECORD_VALUE_TOKEN);
    if (value_token == INVALID)
        return;

    uint2 magnitude;
    if (parse_uint_token(value_token, magnitude))
        hir_expr_int_value[literal_row] = magnitude;
}
