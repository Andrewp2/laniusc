// Per token: the nesting depth change, whether a closure starts here, and
// the binder role of an identifier.
import gpu_index;
import byte_packing;
import generated_token_ids;
import closure_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
RWStructuredBuffer<uint4> marks;
RWStructuredBuffer<uint> roles;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint kind_in_file(uint i, uint count, uint file)
{
    if (i >= count || token_file_id[i] != file)
        return 0u;
    return tokens_out[i].kind;
}

// A closure starts at `|` or `||` where a binary operator cannot stand.
bool prefix_position(uint previous)
{
    return tk_paren_open(previous) || tk_comma(previous) || tk_assign(previous) || previous == TK_RETURN ||
           previous == TK_COLON || previous == TK_ARROW;
}

// The word `move`, which makes the closure after it an owned value.
bool move_word(uint i)
{
    TokenOut token = tokens_out[i];
    if (token.kind != TK_IDENT || token.len != 4u)
        return false;
    return byte_address_load_u8(in_bytes, token.start) == 109u && byte_address_load_u8(in_bytes, token.start + 1u) == 111u &&
           byte_address_load_u8(in_bytes, token.start + 2u) == 118u && byte_address_load_u8(in_bytes, token.start + 3u) == 101u;
}

// Whether the innermost bracket open before token `i` is a parenthesis.
bool inside_parentheses(uint i, uint file)
{
    uint closed = 0u;
    uint j = i;
    while (j > 0u)
    {
        j -= 1u;
        if (token_file_id[j] != file)
            return false;
        uint k = tokens_out[j].kind;
        if (tk_close(k))
        {
            closed += 1u;
        }
        else if (tk_open(k))
        {
            if (closed == 0u)
                return tk_paren_open(k);
            closed -= 1u;
        }
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint count = token_count[0];
    if (i >= count)
        return;

    uint file = token_file_id[i];
    uint kind = tokens_out[i].kind;
    uint previous = i > 0u ? kind_in_file(i - 1u, count, file) : 0u;
    uint next = kind_in_file(i + 1u, count, file);
    uint after_next = kind_in_file(i + 2u, count, file);

    bool bar = kind == TK_PIPE || kind == TK_OROR;
    uint before_previous = i > 1u ? kind_in_file(i - 2u, count, file) : 0u;
    bool moved = bar && previous == TK_IDENT && prefix_position(before_previous) && move_word(i - 1u);
    uint start = bar && (prefix_position(previous) || moved) ? 1u : 0u;
    marks[i] = uint4(tk_depth_delta(kind), start, 0u, 0u);

    uint role = 0u;
    if (kind == TK_IDENT)
    {
        bool typed = next == TK_COLON && after_next != TK_COLON;
        if (previous == TK_LET)
            role = ROLE_LET | (typed ? ROLE_TYPED : 0u);
        else if (previous == TK_FOR)
            role = ROLE_FOR;
        else if (typed && (tk_paren_open(previous) || tk_comma(previous)) && inside_parentheses(i, file))
            role = ROLE_PARAM | ROLE_TYPED;
    }
    roles[i] = role;
}
