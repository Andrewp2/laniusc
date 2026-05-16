// Placeholder for record-driven aggregate WASM body lowering.
//
// The previous implementation was a bounded source/token-shape emitter. That
// violates the backend contract: backend lowering must consume attributed HIR
// and semantic records, not token spelling, source bytes, or helper/body shapes.
//
// Keep this pass wired so the pipeline boundary remains explicit, but do not
// emit or reject here until aggregate lowering is rebuilt as a per-node record
// pipeline.

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

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint target = linear_dispatch_id(tid);
    if (target != 0u && target >= gParams.out_capacity)
        return;

    if (target == 0u && status[2u] == 0u)
        status[2u] = 0u;
}
