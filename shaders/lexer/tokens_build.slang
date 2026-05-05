import utils;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> end_positions;
StructuredBuffer<uint> types_compact;
StructuredBuffer<uint> all_index_compact;
StructuredBuffer<uint> end_positions_all;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};
RWStructuredBuffer<TokenOut> tokens_out;

static const uint TK_IDENT = 1;
static const uint TK_INT = 2;
static const uint TK_WHITE = 3;

static const uint TK_LPAREN = 4;
static const uint TK_RPAREN = 5;
static const uint TK_PLUS = 6;
static const uint TK_STAR = 7;
static const uint TK_ASSIGN = 8;
static const uint TK_SLASH = 9;
static const uint TK_LINE_COMMENT = 10;
static const uint TK_BLOCK_COMMENT = 11;

static const uint TK_LT = 12;
static const uint TK_GT = 13;
static const uint TK_LE = 14;
static const uint TK_GE = 15;
static const uint TK_EQEQ = 16;
static const uint TK_ANDAND = 17;
static const uint TK_OROR = 18;
static const uint TK_NOT = 19;
static const uint TK_LBRACKET = 20;
static const uint TK_RBRACKET = 21;
static const uint TK_LBRACE = 22;
static const uint TK_RBRACE = 23;
static const uint TK_ANGLE_GENERIC = 24;
static const uint TK_AMPERSAND = 25;
static const uint TK_PIPE = 26;
static const uint TK_MINUS = 27;

static const uint TK_CALL_LPAREN = 28;
static const uint TK_GROUP_LPAREN = 29;
static const uint TK_INDEX_LBRACKET = 30;
static const uint TK_ARRAY_LBRACKET = 31;
static const uint TK_STRING = 32;
static const uint TK_FLOAT = 33;
static const uint TK_CHAR = 34;
static const uint TK_PREFIX_PLUS = 58;
static const uint TK_INFIX_PLUS = 59;
static const uint TK_PREFIX_MINUS = 60;
static const uint TK_INFIX_MINUS = 61;
static const uint TK_PUB = 66;
static const uint TK_FN = 67;
static const uint TK_LET = 68;
static const uint TK_RETURN = 69;
static const uint TK_IF = 70;
static const uint TK_ELSE = 71;
static const uint TK_WHILE = 72;
static const uint TK_BREAK = 73;
static const uint TK_CONTINUE = 74;

inline uint retag_keyword(uint kind, uint start, uint len)
{
    if (kind != TK_IDENT)
        return kind;

    if (len == 2u)
    {
        uint b0 = load_byte_at(in_bytes, start);
        uint b1 = load_byte_at(in_bytes, start + 1u);
        if (b0 == 102u && b1 == 110u)
            return TK_FN;
        if (b0 == 105u && b1 == 102u)
            return TK_IF;
    }
    else if (len == 3u)
    {
        uint b0 = load_byte_at(in_bytes, start);
        uint b1 = load_byte_at(in_bytes, start + 1u);
        uint b2 = load_byte_at(in_bytes, start + 2u);
        if (b0 == 112u && b1 == 117u && b2 == 98u)
            return TK_PUB;
        if (b0 == 108u && b1 == 101u && b2 == 116u)
            return TK_LET;
    }
    else if (len == 4u)
    {
        uint b0 = load_byte_at(in_bytes, start);
        uint b1 = load_byte_at(in_bytes, start + 1u);
        uint b2 = load_byte_at(in_bytes, start + 2u);
        uint b3 = load_byte_at(in_bytes, start + 3u);
        if (b0 == 101u && b1 == 108u && b2 == 115u && b3 == 101u)
            return TK_ELSE;
    }
    else if (len == 5u)
    {
        uint b0 = load_byte_at(in_bytes, start);
        uint b1 = load_byte_at(in_bytes, start + 1u);
        uint b2 = load_byte_at(in_bytes, start + 2u);
        uint b3 = load_byte_at(in_bytes, start + 3u);
        uint b4 = load_byte_at(in_bytes, start + 4u);
        if (b0 == 119u && b1 == 104u && b2 == 105u && b3 == 108u && b4 == 101u)
            return TK_WHILE;
        if (b0 == 98u && b1 == 114u && b2 == 101u && b3 == 97u && b4 == 107u)
            return TK_BREAK;
    }
    else if (len == 6u)
    {
        uint b0 = load_byte_at(in_bytes, start);
        uint b1 = load_byte_at(in_bytes, start + 1u);
        uint b2 = load_byte_at(in_bytes, start + 2u);
        uint b3 = load_byte_at(in_bytes, start + 3u);
        uint b4 = load_byte_at(in_bytes, start + 4u);
        uint b5 = load_byte_at(in_bytes, start + 5u);
        if (b0 == 114u && b1 == 101u && b2 == 116u && b3 == 117u && b4 == 114u && b5 == 110u)
            return TK_RETURN;
    }
    else if (len == 8u)
    {
        uint b0 = load_byte_at(in_bytes, start);
        uint b1 = load_byte_at(in_bytes, start + 1u);
        uint b2 = load_byte_at(in_bytes, start + 2u);
        uint b3 = load_byte_at(in_bytes, start + 3u);
        uint b4 = load_byte_at(in_bytes, start + 4u);
        uint b5 = load_byte_at(in_bytes, start + 5u);
        uint b6 = load_byte_at(in_bytes, start + 6u);
        uint b7 = load_byte_at(in_bytes, start + 7u);
        if (b0 == 99u && b1 == 111u && b2 == 110u && b3 == 116u &&
            b4 == 105u && b5 == 110u && b6 == 117u && b7 == 101u)
            return TK_CONTINUE;
    }

    return kind;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void tokens_build(uint3 tid: SV_DispatchThreadID)
{
    uint k = tid.x;
    uint total = token_count[0];
    if (k >= total)
        return;

    uint end_excl = end_positions[k];

    uint all_idx = all_index_compact[k];
    uint all_zero = (all_idx == 0u) ? 0u : (all_idx - 1u);

    uint start = (all_zero == 0u) ? 0u : end_positions_all[all_zero - 1u];

    uint kind = types_compact[k];
    uint prev = (k == 0u) ? 0xFFFFu : types_compact[k - 1];
    if (k > 0u && prev == TK_IDENT)
    {
        uint prev_end_excl = end_positions[k - 1u];
        uint prev_all_idx = all_index_compact[k - 1u];
        uint prev_all_zero = (prev_all_idx == 0u) ? 0u : (prev_all_idx - 1u);
        uint prev_start = (prev_all_zero == 0u) ? 0u : end_positions_all[prev_all_zero - 1u];
        prev = retag_keyword(prev, prev_start, prev_end_excl - prev_start);
    }

    bool ends_primary =
        (prev == TK_IDENT) ||
        (prev == TK_INT) ||
        (prev == TK_FLOAT) ||
        (prev == TK_RPAREN) ||
        (prev == TK_RBRACKET) ||
        (prev == TK_RBRACE) ||
        (prev == TK_ANGLE_GENERIC) ||
        (prev == TK_STRING) ||
        (prev == TK_CHAR);

    if (kind == TK_LPAREN)
    {
        kind = ends_primary ? TK_CALL_LPAREN : TK_GROUP_LPAREN;
    }
    else if (kind == TK_LBRACKET)
    {
        kind = ends_primary ? TK_INDEX_LBRACKET : TK_ARRAY_LBRACKET;
    }
    else if (kind == TK_PLUS)
    {
        kind = ends_primary ? TK_INFIX_PLUS : TK_PREFIX_PLUS;
    }
    else if (kind == TK_MINUS)
    {
        kind = ends_primary ? TK_INFIX_MINUS : TK_PREFIX_MINUS;
    }

    kind = retag_keyword(kind, start, end_excl - start);

    // Write final token
    TokenOut t;
    t.kind = kind;
    t.start = start;
    t.len = end_excl - start;
    tokens_out[k] = t;
}
