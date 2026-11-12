// Per token: a local of a generator adds one to the count of its block, at
// the block's `}`. A block's locals leave scope there.
import gpu_index;
import generator_common;

struct DirectParams
{
    uint token_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<DirectParams> gDirect;
StructuredBuffer<uint> records;
// Inclusive prefix sums: machines, states, transitions, bracket depth.
StructuredBuffer<uint4> scan_a;
// Inclusive prefix sums: generators, yields, loop depth, statement depth.
StructuredBuffer<uint4> scan1;
StructuredBuffer<uint> gens;
RWStructuredBuffer<uint> direct;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (token >= gDirect.token_count || records[token * GR_WORDS + GR_ROLE] != GROLE_LET)
        return;
    GenPlace place = gen_place(records, scan_a, scan1, gens, token);
    if (!place.eligible)
        return;
    uint close = records[token * GR_WORDS + GR_CLOSE];
    if (close < gDirect.token_count)
    {
        uint prior;
        InterlockedAdd(direct[close], 1u, prior);
    }
}
