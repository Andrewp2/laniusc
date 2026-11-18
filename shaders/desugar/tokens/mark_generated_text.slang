// Per byte of a round's generated text: whether it is part of a token,
// whether a token starts at it, and the token kind its piece gives it. A
// copied byte takes the boundaries and kind of the token it copies, a
// constant byte those of the constant's token table, and a generated name or
// number is one token. Two bytes of different pieces join when both are name
// characters, as `__lanius_in_` and `Idle` make `__lanius_in_Idle`; two
// tokens of one copied range never join.
import shared.buffers.gpu_index;
import shared.syntax.generated_token_ids;
import desugaring_layout;

StructuredBuffer<uint> sizes;
ByteAddressBuffer in_bytes;
StructuredBuffer<TokenRow> tokens_out;
StructuredBuffer<uint4> pieces;
StructuredBuffer<uint4> piece_scan;
StructuredBuffer<uint> const_index;
// Per constant byte: bit 0 in a token, bit 1 starts a token, the kind of
// the token that starts there from bit 8.
StructuredBuffer<uint> const_info;
StructuredBuffer<uint> byte_piece;
RWStructuredBuffer<uint> byte_info;
RWStructuredBuffer<uint4> text_marks;

// byte_info bits; the kind from bit 8.
static const uint INFO_IN_TOKEN = 1u;
static const uint INFO_STARTS = 2u;
static const uint INFO_CONTINUES = 4u;

uint text_byte(uint at)
{
    return load_byte(in_bytes, sizes[S_REGION_BASE] + at);
}

// (in token, starts within its piece, kind) of text byte `at`.
uint3 local_info(uint at)
{
    uint index = byte_piece[at];
    uint4 piece = pieces[index];
    uint offset = at - (piece_scan[index].x - piece.x);
    if (piece.y == PIECE_COPY_FIRST || piece.y == PIECE_COPY_NEXT)
    {
        TokenRow row = tokens_out[piece.w];
        uint lead = piece.x - row.len;
        if (offset < lead)
            return uint3(0u, 0u, 0u);
        return uint3(1u, offset == lead ? 1u : 0u, row.kind);
    }
    if (piece.y == PIECE_CONST)
    {
        uint info = const_info[const_index[piece.z * 2u] + offset];
        return uint3(info & 1u, (info >> 1u) & 1u, info >> 8u);
    }
    bool number = piece.y == PIECE_NUMBER || piece.y == PIECE_ID;
    return uint3(1u, offset == 0u ? 1u : 0u, number ? TK_INT : TK_IDENT);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint at = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (at >= sizes[S_REGION])
        return;
    uint3 here = local_info(at);
    bool continues = false;
    if (here.x != 0u && at > 0u)
    {
        uint3 before = local_info(at - 1u);
        if (before.x != 0u)
        {
            uint piece = byte_piece[at];
            if (byte_piece[at - 1u] == piece)
                continues = here.y == 0u;
            else
                continues = pieces[piece].y != PIECE_COPY_NEXT && name_char(text_byte(at - 1u)) &&
                            name_char(text_byte(at));
        }
    }
    bool starts = here.x != 0u && !continues;
    byte_info[at] = here.x | (starts ? INFO_STARTS : 0u) | (continues ? INFO_CONTINUES : 0u) | (here.z << 8u);
    text_marks[at] = uint4(starts ? 1u : 0u, 0u, 0u, 0u);
}
