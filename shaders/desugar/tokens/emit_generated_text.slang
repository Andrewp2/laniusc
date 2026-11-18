// Per word of a round's generated text: four bytes of it, written into the
// round's region of the lexer's byte buffer (compiler/desugar.rs).
// `piece_scan.x` is the text offset just past each piece, so the piece of a
// byte is the first one that ends after it. Each byte also gets its piece
// and its anchor: the byte a diagnostic at it names. A copied byte names the
// byte it copies, which an earlier round may have generated; the host
// follows such a chain to the source.
import shared.buffers.gpu_index;
import desugaring_layout;

StructuredBuffer<uint> sizes;
RWByteAddressBuffer in_bytes;
StructuredBuffer<TokenRow> tokens_out;
StructuredBuffer<uint4> pieces;
StructuredBuffer<uint4> piece_scan;
StructuredBuffer<uint> const_index;
ByteAddressBuffer const_bytes;
RWStructuredBuffer<uint> anchors;
RWStructuredBuffer<uint> byte_piece;

uint text_byte(uint at)
{
    return (in_bytes.Load(at & ~3u) >> ((at & 3u) * 8u)) & 255u;
}

struct RegionBytes : IByteSource
{
    uint byte_at(uint at)
    {
        return text_byte(at);
    }
}

uint const_byte(uint at)
{
    return (const_bytes.Load(at & ~3u) >> ((at & 3u) * 8u)) & 255u;
}

uint piece_of(uint at)
{
    uint lo = 0u;
    uint hi = sizes[S_PIECES];
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (piece_scan[mid].x <= at)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

// The byte at text offset `at` and its anchor.
uint2 output_byte(uint at)
{
    uint index = piece_of(at);
    byte_piece[at] = index;
    if (index >= sizes[S_PIECES])
        return uint2(0u, 0u);
    uint4 piece = pieces[index];
    uint offset = at - (piece_scan[index].x - piece.x);
    TokenRow anchor = tokens_out[piece.w];
    uint kind = piece.y;
    if (kind == PIECE_COPY_FIRST || kind == PIECE_COPY_NEXT)
    {
        uint lead = piece.x - anchor.len;
        if (offset < lead)
            return uint2(32u, anchor.start);
        return uint2(text_byte(anchor.start + offset - lead), anchor.start + offset - lead);
    }
    uint value = 0u;
    if (kind == PIECE_CONST)
        value = const_byte(const_index[piece.z * 2u] + offset);
    else if (kind == PIECE_SNAKE)
        value = snake_text(RegionBytes(), anchor.start, anchor.len, offset);
    else if (kind == PIECE_CAMEL || kind == PIECE_CAMEL_SNAKE)
        value = camel_text(RegionBytes(), anchor.start, anchor.len, kind == PIECE_CAMEL_SNAKE, offset);
    else
        value = decimal_digit(piece.z, piece.x, offset);
    return uint2(value, anchor.start);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    uint first = word * 4u;
    uint region = sizes[S_REGION];
    if (first >= region)
        return;
    uint packed = 0u;
    for (uint j = 0u; j < 4u; j += 1u)
    {
        uint at = first + j;
        if (at < region)
        {
            uint2 value = output_byte(at);
            packed |= value.x << (j * 8u);
            anchors[sizes[S_ANCHOR_BASE] + at] = value.y;
        }
    }
    in_bytes.Store(sizes[S_REGION_BASE] + first, packed);
}
