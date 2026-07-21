// Clear aggregate-layout metadata for the HIR/type-driven WASM aggregate path.
//
// This pass is deliberately metadata-only. It does not inspect source bytes,
// compare token spelling, or accept/reject programs.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> struct_init_field_index;
RWStructuredBuffer<uint> member_result_field_index;
RWStructuredBuffer<uint> wasm_agg_local_width_by_token;
RWStructuredBuffer<uint> wasm_agg_local_base_by_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_id(tid);
    if (i >= gParams.n_tokens)
        return;

    struct_init_field_index[i] = INVALID;
    member_result_field_index[i] = INVALID;
    wasm_agg_local_width_by_token[i] = 0u;
    wasm_agg_local_base_by_token[i] = 0u;
}
