// Per token: writes the token into the two lists it is marked for, at its
// ordinal. `scan` is the inclusive prefix sum of `marks`, so the ordinal of
// a marked token is its sum minus one. The other two components are depths.
import gpu_index;

struct ListParams
{
    uint token_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<ListParams> gLists;
StructuredBuffer<uint4> marks;
StructuredBuffer<uint4> scan;
RWStructuredBuffer<uint> list_x;
RWStructuredBuffer<uint> list_y;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (token >= gLists.token_count)
        return;
    uint4 mark = marks[token];
    uint4 ordinal = scan[token];
    if (mark.x != 0u)
        list_x[ordinal.x - 1u] = token;
    if (mark.y != 0u)
        list_y[ordinal.y - 1u] = token;
}
