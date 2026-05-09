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
static const uint TK_PUB = 66;
static const uint TK_FN = 67;
static const uint TK_LET = 68;
static const uint TK_RETURN = 69;
static const uint TK_IF = 70;
static const uint TK_ELSE = 71;
static const uint TK_WHILE = 72;
static const uint TK_BREAK = 73;
static const uint TK_CONTINUE = 74;
static const uint TK_TRUE = 90;
static const uint TK_FALSE = 91;

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
        if (b0 == 116u && b1 == 114u && b2 == 117u && b3 == 101u)
            return TK_TRUE;
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
        if (b0 == 102u && b1 == 97u && b2 == 108u && b3 == 115u && b4 == 101u)
            return TK_FALSE;
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

inline uint compact_token_start(uint token_index)
{
    uint all_idx = all_index_compact[token_index];
    uint all_zero = (all_idx == 0u) ? 0u : (all_idx - 1u);
    return (all_zero == 0u) ? 0u : end_positions_all[all_zero - 1u];
}

inline uint retag_compact_kind(uint token_index)
{
    uint kind = types_compact[token_index];
    if (kind == TK_IDENT)
    {
        uint end_excl = end_positions[token_index];
        uint start = compact_token_start(token_index);
        kind = retag_keyword(kind, start, end_excl - start);
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
    uint start = compact_token_start(k);
    uint kind = retag_compact_kind(k);

    // Write final token
    TokenOut t;
    t.kind = kind;
    t.start = start;
    t.len = end_excl - start;
    tokens_out[k] = t;
}
