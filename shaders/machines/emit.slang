// Per output word: four bytes of the expanded pack. `piece_scan.x` is the
// output offset just past each piece, so the piece of a byte is the first
// one that ends after it.
import gpu_index;
import byte_packing;
import machine_common;

struct EmitParams
{
    uint out_len;
    uint piece_count;
    uint reserved0;
    uint reserved1;
};

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

ConstantBuffer<EmitParams> gEmit;
ByteAddressBuffer in_bytes;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint4> pieces;
StructuredBuffer<uint4> piece_scan;
StructuredBuffer<uint> const_index;
ByteAddressBuffer const_bytes;
RWStructuredBuffer<uint> out_words;

static const uint DISPATCH_X_STRIDE = 16776960u;

// Byte `offset` of the snake_case form of token `name`.
uint snake_byte(uint name, uint offset)
{
    TokenOut row = tokens_out[name];
    uint len = min(row.len, MAX_NAME);
    uint at = 0u;
    uint previous = 0u;
    for (uint i = 0u; i < len; i += 1u)
    {
        uint current = byte_address_load_u8(in_bytes, row.start + i);
        uint next = i + 1u < len ? byte_address_load_u8(in_bytes, row.start + i + 1u) : 0u;
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

uint output_byte(uint at)
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
    if (lo >= gEmit.piece_count)
        return 0u;
    uint4 piece = pieces[lo];
    uint offset = at - (piece_scan[lo].x - piece.x);
    if (piece.y == PIECE_COPY)
        return byte_address_load_u8(in_bytes, piece.z + offset);
    if (piece.y == PIECE_CONST)
        return byte_address_load_u8(const_bytes, const_index[piece.z * 2u] + offset);
    if (piece.y == PIECE_SNAKE)
        return snake_byte(piece.w, offset);

    // A decimal digit, most significant first.
    uint divisor = 1u;
    for (uint digit = offset + 1u; digit < piece.x && digit < 10u; digit += 1u)
        divisor *= 10u;
    return 48u + (piece.z / divisor) % 10u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint first = word * 4u;
    if (first >= gEmit.out_len)
        return;
    uint packed = 0u;
    for (uint j = 0u; j < 4u; j += 1u)
    {
        uint at = first + j;
        if (at < gEmit.out_len)
            packed |= output_byte(at) << (j * 8u);
    }
    out_words[word] = packed;
}
