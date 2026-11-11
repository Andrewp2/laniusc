// Per token: names that start with `__lanius_` belong to generated code, so
// a source file may not use one. Generated text reaches this kernel too: the
// copies of generic functions, and files that generators or the closure pass
// wrote, which use the names of those passes.
import gpu_index;
import byte_packing;
import generated_token_ids;
import machine_common;

struct ReservedParams
{
    uint token_count;
    uint reserved0;
    uint explain_word;
    uint explain_key;
};

ConstantBuffer<ReservedParams> gReserved;
StructuredBuffer<uint> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
// Per file: bit 0 when generators wrote it, bit 1 when the closure pass did.
StructuredBuffer<uint> file_flags;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> detail;

static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint FILE_GENERATORS = 1u;
static const uint FILE_CLOSURES = 2u;

// Whether the `count` bytes of token `t` from `offset` are the bytes packed
// in `low` and `high`, least significant first.
bool text_at(uint t, uint offset, uint low, uint high, uint count)
{
    if (token_len(tokens_out, t) < offset + count)
        return false;
    for (uint i = 0u; i < count; i += 1u)
    {
        uint expected = i < 4u ? (low >> (i * 8u)) & 255u : (high >> ((i - 4u) * 8u)) & 255u;
        if (token_byte(tokens_out, in_bytes, t, offset + i) != expected)
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (t >= gReserved.token_count || token_kind(tokens_out, t) != TK_IDENT)
        return;
    // "__lanius", "_"
    if (!text_at(t, 0u, 0x616c5f5fu, 0x7375696eu, 8u) || !text_at(t, 8u, 0x5fu, 0u, 1u))
        return;
    // "inst_": the copies of generic functions.
    if (text_at(t, 9u, 0x74736e69u, 0x5fu, 5u))
        return;
    uint flags = file_flags[token_file_id[t]];
    // "gen_"
    if ((flags & FILE_GENERATORS) != 0u && text_at(t, 9u, 0x5f6e6567u, 0u, 4u))
        return;
    // "closure_", and "r" alone.
    if ((flags & FILE_CLOSURES) != 0u &&
        (text_at(t, 9u, 0x736f6c63u, 0x5f657275u, 8u) ||
         (token_len(tokens_out, t) == 10u && text_at(t, 9u, 0x72u, 0u, 1u))))
        return;
    machine_error(status, detail, tokens_out, gReserved.explain_word, gReserved.explain_key, STATUS_RESERVED, t,
                  E_RESERVED, 0u, 0u, 0u);
}
