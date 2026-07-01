// Retired collection boundary.
//
// Function discovery now owns HIR function counting and main-entrypoint
// selection through token-keyed WASM function records. Keep this stage wired as
// an explicit pipeline boundary while it no longer publishes body-plan facts.

import atomics;
import body_common;

StructuredBuffer<uint> status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node == INVALID && status[2u] == ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
}
