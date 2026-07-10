import gpu_index;
import utils;
import atomics;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> end_positions;
StructuredBuffer<uint> types_compact;
StructuredBuffer<uint> all_index_compact;
StructuredBuffer<uint> end_positions_all;
StructuredBuffer<uint> source_file_count;
StructuredBuffer<uint> source_file_start;
StructuredBuffer<uint> source_file_len;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};
RWStructuredBuffer<TokenOut> tokens_out;
RWStructuredBuffer<uint> token_file_id;
RWStructuredBuffer<uint> parser_feature_flags;

static const uint TK_IDENT = 1;
static const uint TK_INT = 2;
static const uint TK_ASSIGN = 8;
static const uint TK_LBRACKET = 20;
static const uint TK_RBRACKET = 21;
static const uint TK_DOT = 35;
static const uint TK_FLOAT = 33;
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
static const uint TK_WHERE = 104;
static const uint TK_SELF_VALUE = 105;
static const uint TK_DOT_DOT = 182;
static const uint TK_DOT_DOT_EQUAL = 189;
static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint PARSER_FEATURE_ARRAYS = 0x00000002u;
static const uint PARSER_FEATURE_ENUMS = 0x00000004u;
static const uint PARSER_FEATURE_MATCHES = 0x00000008u;

uint parser_features_for_lexical_token(uint kind)
{
    uint flags = 0u;
    if (kind == TK_LBRACKET || kind == TK_RBRACKET)
        flags |= PARSER_FEATURE_ARRAYS;
    if (kind == TK_ENUM)
        flags |= PARSER_FEATURE_ENUMS;
    if (kind == TK_MATCH)
        flags |= PARSER_FEATURE_MATCHES;
    return flags;
}

uint2 file_start_and_id_for_token_end(uint end_excl)
{
    if (end_excl == 0u)
        return uint2(0u, INVALID);

    uint pos = end_excl - 1u;
    uint count = source_file_count[0];
    uint lo = 0u;
    uint hi = count;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        if (source_file_start[mid] <= pos)
            lo = mid + 1u;
        else
            hi = mid;
    }

    if (lo == 0u)
        return uint2(0u, INVALID);

    uint file_i = lo - 1u;
    uint start = source_file_start[file_i];
    uint end = start + source_file_len[file_i];
    if (pos >= start && pos < end)
        return uint2(start, file_i);
    return uint2(0u, INVALID);
}

uint retag_keyword(uint kind, uint start, uint len)
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
        if (b0 == 115u && b1 == 101u && b2 == 108u && b3 == 102u)
            return TK_SELF_VALUE;
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
        if (b0 == 119u && b1 == 104u && b2 == 101u && b3 == 114u && b4 == 101u)
            return TK_WHERE;
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

uint compact_token_start(uint token_index)
{
    uint all_idx = all_index_compact[token_index];
    uint all_zero = (all_idx == 0u) ? 0u : (all_idx - 1u);
    return (all_zero == 0u) ? 0u : end_positions_all[all_zero - 1u];
}

uint retag_compact_kind(uint token_index, uint start, uint end_excl)
{
    uint kind = types_compact[token_index];
    if (kind == TK_IDENT)
    {
        kind = retag_keyword(kind, start, end_excl - start);
    }
    return kind;
}

bool token_is_single_dot(uint token_index, uint start, uint end_excl)
{
    return retag_compact_kind(token_index, start, end_excl) == TK_DOT
        && end_excl == start + 1u;
}

bool float_token_ends_with_dot(uint kind, uint start, uint end_excl)
{
    return kind == TK_FLOAT
        && end_excl > start
        && load_byte_at(in_bytes, end_excl - 1u) == 46u;
}

bool next_token_is_adjacent_dot(uint token_index, uint end_excl, uint file_id, uint total)
{
    uint next_index = token_index + 1u;
    if (next_index >= total)
        return false;

    uint next_end = end_positions[next_index];
    uint2 next_file_info = file_start_and_id_for_token_end(next_end);
    if (next_file_info.y != file_id)
        return false;

    uint next_start = compact_token_start(next_index);
    next_start = max(next_start, next_file_info.x);
    return next_start == end_excl && token_is_single_dot(next_index, next_start, next_end);
}

bool next_token_is_adjacent_assign(uint token_index, uint end_excl, uint file_id, uint total)
{
    uint next_index = token_index + 1u;
    if (next_index >= total)
        return false;

    uint next_end = end_positions[next_index];
    uint2 next_file_info = file_start_and_id_for_token_end(next_end);
    if (next_file_info.y != file_id)
        return false;

    uint next_start = compact_token_start(next_index);
    next_start = max(next_start, next_file_info.x);
    return next_start == end_excl &&
           retag_compact_kind(next_index, next_start, next_end) == TK_ASSIGN &&
           next_end == next_start + 1u;
}

bool previous_token_is_adjacent_float_dot(uint token_index, uint start, uint file_id)
{
    if (token_index == 0u)
        return false;

    uint prev_index = token_index - 1u;
    uint prev_end = end_positions[prev_index];
    uint2 prev_file_info = file_start_and_id_for_token_end(prev_end);
    if (prev_file_info.y != file_id)
        return false;

    uint prev_start = compact_token_start(prev_index);
    prev_start = max(prev_start, prev_file_info.x);
    uint prev_kind = retag_compact_kind(prev_index, prev_start, prev_end);
    return prev_end == start && float_token_ends_with_dot(prev_kind, prev_start, prev_end);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void tokens_build(uint3 tid: SV_DispatchThreadID)
{
    uint k = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint total = token_count[0];

    if (k >= total)
        return;

    uint end_excl = end_positions[k];
    uint2 file_info = file_start_and_id_for_token_end(end_excl);
    uint start = compact_token_start(k);
    start = max(start, file_info.x);
    uint kind = retag_compact_kind(k, start, end_excl);

    if (float_token_ends_with_dot(kind, start, end_excl)
        && next_token_is_adjacent_dot(k, end_excl, file_info.y, total))
    {
        kind = TK_INT;
        end_excl -= 1u;
    }
    else if (kind == TK_DOT
        && previous_token_is_adjacent_float_dot(k, start, file_info.y))
    {
        kind = TK_DOT_DOT;
        start -= 1u;
    }

    if (kind == TK_DOT_DOT
        && next_token_is_adjacent_assign(k, end_excl, file_info.y, total))
    {
        kind = TK_DOT_DOT_EQUAL;
    }

    // Write final token
    TokenOut t;
    t.kind = kind;
    t.start = start;
    t.len = end_excl - start;
    tokens_out[k] = t;
    token_file_id[k] = file_info.y;
    uint parser_features = parser_features_for_lexical_token(kind);
    if (parser_features != 0u)
        atomic_u32_or(parser_feature_flags, 0u, parser_features);
}
