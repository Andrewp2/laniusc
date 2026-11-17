// Per piece after the expansion: its row and owner. A feature's RANGE piece
// of `count` tokens becomes one COPY piece per token, with one space before
// a token that a gap separates from the one before it; every other piece is
// copied and gets its length. `fpiece_scan.x` is the inclusive prefix sum of
// the counts of the feature's pieces.
import gpu_index;
import desugar_common;

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenRow> tokens_out;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint4> fpieces;
StructuredBuffer<uint> fpiece_owner;
StructuredBuffer<uint4> fpiece_scan;
StructuredBuffer<uint> const_index;
RWStructuredBuffer<uint4> pieces;
RWStructuredBuffer<uint> piece_owner;

struct SourceBytes : IByteSource
{
    uint byte_at(uint at)
    {
        return load_byte(in_bytes, at);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint e = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (e >= sizes[S_PIECES])
        return;
    uint lo = 0u;
    uint hi = sizes[S_FPIECES];
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (fpiece_scan[mid].x <= e)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint4 piece = fpieces[lo];
    piece_owner[e] = fpiece_owner[lo];
    uint kind = piece.y;
    if (kind == PIECE_RANGE)
    {
        uint j = e - (fpiece_scan[lo].x - piece.x);
        uint token = piece.z + j;
        TokenRow row = tokens_out[token];
        // A copied token after a gap keeps one space before it.
        uint lead = 0u;
        if (j > 0u)
        {
            TokenRow previous = tokens_out[token - 1u];
            lead = previous.start + previous.len < row.start ? 1u : 0u;
        }
        pieces[e] = uint4(row.len + lead, j == 0u ? PIECE_COPY_FIRST : PIECE_COPY_NEXT, token, token);
        return;
    }
    uint len = 0u;
    if (kind == PIECE_CONST)
        len = const_index[piece.z * 2u + 1u];
    else if (kind == PIECE_NUMBER)
        len = decimal_digits(piece.z);
    else if (kind == PIECE_ID)
        len = ID_DIGITS;
    else
    {
        TokenRow name = tokens_out[piece.w];
        if (kind == PIECE_SNAKE)
            len = snake_text(SourceBytes(), name.start, name.len, DS_NONE);
        else
            len = camel_text(SourceBytes(), name.start, name.len, kind == PIECE_CAMEL_SNAKE, DS_NONE);
    }
    pieces[e] = uint4(len, kind, piece.z, piece.w);
}
