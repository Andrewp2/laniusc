// shaders/parser/pack_varlen.slang
// -------------------------------------------------------------------------------------
// 🤖 Placeholder kernel for a future GPU packing path:
// 🤖 Given per-pair lengths and prefix offsets, scatter the variable-length records.
// 🤖 We'll wire this up after we reuse your scan passes for exclusive offsets.
// -------------------------------------------------------------------------------------
struct ActionHeader
{
    uint push_len;
    uint emit_len;
    uint pop_tag;
    uint pop_count;
};

cbuffer Params
{
    uint n_pairs;    // 🤖 length of headers[]
    uint total_push; // 🤖 sum(push_len)
    uint total_emit; // 🤖 sum(emit_len)
    uint _pad;
}

StructuredBuffer<ActionHeader> headers : register(t0);
StructuredBuffer<uint> push_offsets : register(t1);
StructuredBuffer<uint> emit_offsets : register(t2);

// In a later step these would be the variable-length payload dictionaries (per (prev,this))
// Here we leave the payloads CPU-side for MVP.

RWByteAddressBuffer out_push : register(u0);
RWByteAddressBuffer out_emit : register(u1);

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    // 🤖 Will implement once offsets come from a GPU scan pass
}
