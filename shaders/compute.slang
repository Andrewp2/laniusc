// 🤖 A tiny Slang compute shader writing indices into a storage buffer.
//    No explicit binding/registers; we'll query them via reflection at runtime.

RWStructuredBuffer<uint> data;

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x < data.getCount())
        data[tid.x] = tid.x;
}
