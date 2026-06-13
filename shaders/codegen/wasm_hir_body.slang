// Fail-closed placeholder for the retired single-body WASM byte emitter.
//
// The previous shader walked HIR nodes inside one invocation to find main,
// locals, returns, and statements. That source-sized body scan is not the
// paper/Pareas pass shape. WASM lowering should be rebuilt as record
// publication, byte counts, prefix sums, and scatters before it can emit bytes
// again.

RWStructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;

    body_status[0u] = 0u;
    body_status[1u] = 0u;

    if (status[2u] == 0u || status[2u] == ERR_UNSUPPORTED_SOURCE_SHAPE)
    {
        status[1u] = 0u;
        status[2u] = ERR_UNSUPPORTED_SOURCE_SHAPE;
        status[3u] = INVALID;
    }
}
