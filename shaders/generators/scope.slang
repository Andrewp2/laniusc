// Per pair of a local and a `yield` it is in scope of: writes the local into
// the yield's slots, at the local's position among the locals in scope.
import gpu_index;
import generator_common;

struct ScopeParams
{
    uint token_count;
    uint pair_count;
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<ScopeParams> gScope;
// Inclusive prefix sums: generators, yields, loop depth, statement depth.
StructuredBuffer<uint4> scan1;
// Inclusive prefix sums: parameters, locals, locals in scope, depth in the
// loops that hold a `yield`.
StructuredBuffer<uint4> scan2;
// Inclusive prefix sums: slots of yields, pairs of locals, pieces.
StructuredBuffer<uint4> scan3;
StructuredBuffer<uint> yields;
RWStructuredBuffer<uint> scope;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint pair = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (pair >= gScope.pair_count)
        return;
    // The local of this pair: the first token whose pairs end after it.
    uint lo = 0u;
    uint hi = gScope.token_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (scan3[mid].y <= pair)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= gScope.token_count)
        return;
    uint local = lo;
    uint nth = pair - (local > 0u ? scan3[local - 1u].y : 0u);
    uint target = yields[scan1[local].y + nth];
    uint slot = scan3[target].x - scan2[target].z + scan2[local].z - 1u;
    scope[slot] = local;
}
