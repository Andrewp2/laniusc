// Per token, on the error path of a build whose lexer found a name with the
// prefix of generated names (`__lanius_`, R5): the first such token. The
// lexer's token build sets DESUGAR_RESERVED by the same rule, and no round
// of the desugaring runs then, so the tokens are the source's.
import gpu_index;
import generated_token_ids;
import machine_common;

struct ReservedParams
{
    uint token_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<ReservedParams> gReserved;
StructuredBuffer<uint> tokens_out;
ByteAddressBuffer in_bytes;
RWStructuredBuffer<uint> status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (t >= gReserved.token_count || token_kind(tokens_out, t) != TK_IDENT || token_len(tokens_out, t) < 9u)
        return;
    // "__la", "nius", "_", packed low byte first.
    for (uint k = 0u; k < 9u; k += 1u)
    {
        uint word = k < 4u ? 0x616c5f5fu : (k < 8u ? 0x7375696eu : 0x5fu);
        if (token_byte(tokens_out, in_bytes, t, k) != ((word >> ((k & 3u) * 8u)) & 255u))
            return;
    }
    uint prior;
    InterlockedMin(status[0], t, prior);
}
