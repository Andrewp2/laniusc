// Per token: the nesting depth change and whether a closure starts here.
// The inclusive prefix sum of the two gives each token its depth and the
// number of the closure that starts at it (read_closure_records.slang).
import shared.buffers.gpu_index;
import shared.buffers.byte_packing;
import shared.syntax.generated_token_ids;
import closure_layout;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

// Word 0 of the round's sizes: the tokens it reads.
StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
RWStructuredBuffer<uint4> marks;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint kind_in_file(uint i, uint count, uint file)
{
    if (i >= count || token_file_id[i] != file)
        return 0u;
    return tokens_out[i].kind;
}

// A closure starts at `|` or `||` where a binary operator cannot stand. The
// lexer's token build sets the closure feature bit by the same rule.
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

    bool bar = kind == TK_PIPE || kind == TK_OROR;
    uint before_previous = i > 1u ? kind_in_file(i - 2u, count, file) : 0u;
    bool moved = bar && previous == TK_IDENT && prefix_position(before_previous) && move_word(i - 1u);
    uint start = bar && (prefix_position(previous) || moved) ? 1u : 0u;
    marks[i] = uint4(tk_depth_delta(kind), start, 0u, 0u);
}
