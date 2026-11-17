// Per generated token that is the first of its owner: how many tokens the
// owner gets and which comes first, in the owner's splice row. Owners do not
// decrease along the generated tokens.
import gpu_index;
import desugar_common;

StructuredBuffer<uint> sizes;
StructuredBuffer<uint> generated_owner;
RWStructuredBuffer<uint4> splice_marks;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint g = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    uint count = sizes[S_GENERATED];
    if (g >= count)
        return;
    uint owner = generated_owner[g];
    if (g > 0u && generated_owner[g - 1u] == owner)
        return;
    uint lo = g + 1u;
    uint hi = count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (generated_owner[mid] <= owner)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint4 row = splice_marks[owner];
    splice_marks[owner] = uint4(row.x, lo - g, g, 0u);
}
