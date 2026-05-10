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
static const uint TK_CONST = 92;
static const uint TK_ENUM = 93;
static const uint TK_STRUCT = 94;
static const uint TK_MATCH = 95;
static const uint TK_IMPORT = 96;
static const uint TK_MODULE = 97;
static const uint TK_IMPL = 98;
static const uint TK_TRAIT = 99;
static const uint TK_FOR = 100;
static const uint TK_IN = 101;
static const uint TK_EXTERN = 102;
static const uint TK_TYPE = 103;

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
        if (b0 == 105u && b1 == 110u)
            return TK_IN;
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
        if (b0 == 102u && b1 == 111u && b2 == 114u)
            return TK_FOR;
    }
    else if (len == 4u)
    {
        uint b0 = load_byte_at(in_bytes, start);
        uint b1 = load_byte_at(in_bytes, start + 1u);
        uint b2 = load_byte_at(in_bytes, start + 2u);
        uint b3 = load_byte_at(in_bytes, start + 3u);
        if (b0 == 101u && b1 == 108u && b2 == 115u && b3 == 101u)
            return TK_ELSE;
        if (b0 == 101u && b1 == 110u && b2 == 117u && b3 == 109u)
            return TK_ENUM;
        if (b0 == 105u && b1 == 109u && b2 == 112u && b3 == 108u)
            return TK_IMPL;
        if (b0 == 116u && b1 == 114u && b2 == 117u && b3 == 101u)
            return TK_TRUE;
        if (b0 == 116u && b1 == 121u && b2 == 112u && b3 == 101u)
            return TK_TYPE;
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
        if (b0 == 99u && b1 == 111u && b2 == 110u && b3 == 115u && b4 == 116u)
            return TK_CONST;
        if (b0 == 109u && b1 == 97u && b2 == 116u && b3 == 99u && b4 == 104u)
            return TK_MATCH;
        if (b0 == 116u && b1 == 114u && b2 == 97u && b3 == 105u && b4 == 116u)
            return TK_TRAIT;
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
        if (b0 == 115u && b1 == 116u && b2 == 114u && b3 == 117u && b4 == 99u && b5 == 116u)
            return TK_STRUCT;
        if (b0 == 105u && b1 == 109u && b2 == 112u && b3 == 111u && b4 == 114u && b5 == 116u)
            return TK_IMPORT;
        if (b0 == 109u && b1 == 111u && b2 == 100u && b3 == 117u && b4 == 108u && b5 == 101u)
            return TK_MODULE;
        if (b0 == 101u && b1 == 120u && b2 == 116u && b3 == 101u && b4 == 114u && b5 == 110u)
            return TK_EXTERN;
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
