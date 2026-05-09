struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> unpacked_words;
RWStructuredBuffer<uint> packed_words;
StructuredBuffer<uint> status;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[1u] != 1u && status[1u] != 5u)
        return;

    uint len = min(status[0u], gParams.out_capacity);
    uint word_i = linear_dispatch_id(tid);
    uint word_count = (len + 3u) / 4u;
    if (word_i >= word_count)
        return;

    uint pos = word_i * 4u;
    uint b0 = pos + 0u < len ? (unpacked_words[pos + 0u] & 0xffu) : 0u;
    uint b1 = pos + 1u < len ? (unpacked_words[pos + 1u] & 0xffu) : 0u;
    uint b2 = pos + 2u < len ? (unpacked_words[pos + 2u] & 0xffu) : 0u;
    uint b3 = pos + 3u < len ? (unpacked_words[pos + 3u] & 0xffu) : 0u;
    packed_words[word_i] = b0 | (b1 << 8u) | (b2 << 16u) | (b3 << 24u);
}
