// Placeholder for record-driven assertion/trap WASM lowering.
//
// The removed implementation recognized a narrow helper body shape for
// assertion wrappers. That is not a backend architecture we can keep: assertion
// lowering has to consume resolved intrinsic call records and instruction
// records rather than source/body shapes.
//
// This pass remains wired as an explicit pipeline boundary and intentionally
// does not overwrite or reject a module emitted by earlier record-compatible
// stages.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> status;

static const uint DISPATCH_X_STRIDE = 16776960u;

bool module_already_emitted()
{
    return status[1u] == 1u || status[1u] == 2u || status[1u] == 3u ||
           status[1u] == 5u;
}

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (module_already_emitted())
        return;

    uint target = linear_dispatch_id(tid);
    if (target != 0u && target >= gParams.out_capacity)
        return;

    if (target == 0u && status[2u] == 0u)
        status[2u] = 0u;
}
