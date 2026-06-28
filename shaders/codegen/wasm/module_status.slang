// Publish final WASM module status from body status and module capacity.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> status;

static const uint BODY_OFF = 80u;
static const uint MODULE_STATUS_SLOT_COUNT = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool prior_module_or_error(uint mode, uint error_code)
{
    return mode == 1u || mode == 2u || mode == 5u || error_code != 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot = linear_dispatch_id(tid);
    uint input_mode = status[1u];
    uint input_error_code = status[2u];
    GroupMemoryBarrierWithGroupSync();

    if (slot >= MODULE_STATUS_SLOT_COUNT ||
        prior_module_or_error(input_mode, input_error_code))
        return;

    uint body_len = body_status[0u];
    bool body_ok = body_status[1u] != 0u;
    uint module_len = BODY_OFF + body_len;
    bool ok = body_ok && module_len <= gParams.out_capacity;

    if (slot == 0u)
        status[0u] = module_len;
    else
        status[1u] = ok ? 3u : 0u;
}
