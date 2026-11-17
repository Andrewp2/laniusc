// Per word of generated text: four bytes of the machines' expansion, written
// into the region of the lexer's byte buffer after the source
// (compiler/desugar.rs). `piece_scan.x` is the text offset just past each
// piece, so the piece of a byte is the first one that ends after it. Each
// byte also gets its anchor, the source byte a diagnostic at it names, and
// its piece.
import gpu_index;
import machine_common;

struct EmitParams
{
    uint region_len;
    uint piece_count;
    uint region_base;
    uint token_count;
};

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

ConstantBuffer<EmitParams> gEmit;
RWByteAddressBuffer in_bytes;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint4> pieces;
StructuredBuffer<uint4> piece_scan;
StructuredBuffer<uint> const_index;
ByteAddressBuffer const_bytes;
RWStructuredBuffer<uint> anchors;
RWStructuredBuffer<uint> byte_piece;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint source_byte(uint at)
{
    return (in_bytes.Load(at & ~3u) >> ((at & 3u) * 8u)) & 255u;
}

uint const_byte(uint at)
{
    return (const_bytes.Load(at & ~3u) >> ((at & 3u) * 8u)) & 255u;
}

// Byte `offset` of the snake_case form of token `name`.
uint snake_byte(uint name, uint offset)
{
    TokenOut row = tokens_out[name];
    uint len = min(row.len, MAX_NAME);
    uint at = 0u;
    uint previous = 0u;
    for (uint i = 0u; i < len; i += 1u)
    {
        uint current = source_byte(row.start + i);
        uint next = i + 1u < len ? source_byte(row.start + i + 1u) : 0u;
        if (snake_boundary(previous, current, next))
        {
            if (at == offset)
                return 95u;
            at += 1u;
        }
        if (at == offset)
            return ascii_upper(current) ? current + 32u : current;
        at += 1u;
        previous = current;
    }
    return 0u;
}

uint piece_of(uint at)
{
    uint lo = 0u;
    uint hi = gEmit.piece_count;
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
    if (index >= gEmit.piece_count)
        return uint2(0u, 0u);
    uint4 piece = pieces[index];
    uint offset = at - (piece_scan[index].x - piece.x);
    uint anchor = tokens_out[piece.w].start;
    if (piece.y == PIECE_COPY)
        return uint2(source_byte(piece.z + offset), piece.z + offset);
    if (piece.y == PIECE_CONST)
        return uint2(const_byte(const_index[piece.z * 2u] + offset), anchor);
    if (piece.y == PIECE_SNAKE)
        return uint2(snake_byte(piece.w, offset), anchor);

    // A decimal digit, most significant first.
    uint divisor = 1u;
    for (uint digit = offset + 1u; digit < piece.x && digit < 10u; digit += 1u)
        divisor *= 10u;
    return uint2(48u + (piece.z / divisor) % 10u, anchor);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint first = word * 4u;
    if (first >= gEmit.region_len)
        return;
    uint packed = 0u;
    for (uint j = 0u; j < 4u; j += 1u)
    {
        uint at = first + j;
        if (at < gEmit.region_len)
        {
            uint2 value = output_byte(at);
            packed |= value.x << (j * 8u);
            anchors[at] = value.y;
        }
    }
    in_bytes.Store(gEmit.region_base + first, packed);
}
