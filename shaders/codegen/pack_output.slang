import byte_packing;
import gpu_index;

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
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
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
    packed_words[word_i] = packed_u8_word_from_unpacked(unpacked_words, pos, len);
}
