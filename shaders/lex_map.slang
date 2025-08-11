// shaders/lex_map.slang
// Stage 1: chars → unary-function ids

struct LexParams
{
    uint n;
    uint m;
    uint identity_id;
};
ConstantBuffer<LexParams> gParams;

StructuredBuffer<uint> in_bytes;     // length n
StructuredBuffer<uint> char_to_func; // 256

RWStructuredBuffer<uint> f_ping; // length n

[shader("compute")]
[numthreads(128, 1, 1)]
void map_chars(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint b = in_bytes[i] & 255u;
    f_ping[i] = char_to_func[b];
}
