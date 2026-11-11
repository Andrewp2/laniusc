// Per token: writes the token into each list it is marked for, at its
// ordinal. `scan` is the inclusive prefix sum of `marks`, so the ordinal of
// a marked token is its sum minus one. The fourth component is a list only
// when `fourth` is set: in the first marks it is the bracket depth.
import gpu_index;

struct ListParams
{
    uint token_count;
    uint fourth;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<ListParams> gLists;
StructuredBuffer<uint4> marks;
StructuredBuffer<uint4> scan;
RWStructuredBuffer<uint> list_x;
RWStructuredBuffer<uint> list_y;
RWStructuredBuffer<uint> list_z;
RWStructuredBuffer<uint> list_w;

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
    if (mark.z != 0u)
        list_z[ordinal.z - 1u] = token;
    if (gLists.fourth != 0u && mark.w != 0u)
        list_w[ordinal.w - 1u] = token;
}
