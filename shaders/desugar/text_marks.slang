// Per byte of generated text: whether it is part of a token, whether a token
// starts at it, and the token kind its piece gives it. The token
// boundaries come from the pieces: a copied byte takes the boundaries of
// its source token, a constant byte those of the constant's token table,
// and a snake_case name or a number is one token. Two bytes of different
// pieces join when both are name characters, as `__lanius_in_` and `Idle`
// make `__lanius_in_Idle`.
import gpu_index;
import generated_token_ids;
import machines.machine_common;
import desugar_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> sizes;
ByteAddressBuffer in_bytes;
StructuredBuffer<TokenOut> tokens_out;
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
    uint address = sizes[S_REGION_BASE] + at;
    return (in_bytes.Load(address & ~3u) >> ((address & 3u) * 8u)) & 255u;
}

bool name_char(uint c)
{
    return (c >= 48u && c <= 57u) || (c >= 65u && c <= 90u) || (c >= 97u && c <= 122u) || c == 95u;
}

// The source token that holds source byte `s`, or MC_NONE.
uint source_token_at(uint s)
{
    uint lo = 0u;
    uint hi = sizes[S_TOKENS];
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (tokens_out[mid].start <= s)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo == 0u)
        return MC_NONE;
    TokenOut row = tokens_out[lo - 1u];
    return s < row.start + row.len ? lo - 1u : MC_NONE;
}

// (in token, starts within its piece, kind) of text byte `at`.
uint3 local_info(uint at)
{
    uint index = byte_piece[at];
    uint4 piece = pieces[index];
    uint offset = at - (piece_scan[index].x - piece.x);
    if (piece.y == PIECE_COPY)
    {
        uint s = piece.z + offset;
        uint t = source_token_at(s);
        if (t == MC_NONE)
            return uint3(0u, 0u, 0u);
        TokenOut row = tokens_out[t];
        return uint3(1u, s == row.start || offset == 0u ? 1u : 0u, row.kind);
    }
    if (piece.y == PIECE_CONST)
    {
        uint info = const_info[const_index[piece.z * 2u] + offset];
        return uint3(info & 1u, (info >> 1u) & 1u, info >> 8u);
    }
    return uint3(1u, offset == 0u ? 1u : 0u, piece.y == PIECE_NUMBER ? TK_INT : TK_IDENT);
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
            if (byte_piece[at - 1u] == byte_piece[at])
                continues = here.y == 0u;
            else
                continues = name_char(text_byte(at - 1u)) && name_char(text_byte(at));
        }
    }
    bool starts = here.x != 0u && !continues;
    byte_info[at] = here.x | (starts ? INFO_STARTS : 0u) | (continues ? INFO_CONTINUES : 0u) | (here.z << 8u);
    text_marks[at] = uint4(starts ? 1u : 0u, 0u, 0u, 0u);
}
