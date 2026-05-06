struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint segment_count;
    uint segment_len;
    uint block_count;
    uint scan_step;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> token_hir_role;
RWStructuredBuffer<uint> token_codegen_flags;
RWStructuredBuffer<int> token_function_delta;
RWStructuredBuffer<uint> codegen_bounds;

static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i == 0u)
    {
        codegen_bounds[0u] = INVALID;
        codegen_bounds[1u] = 0u;
    }
    if (i >= gParams.n_tokens)
        return;
    token_hir_role[i] = 0u;
    token_codegen_flags[i] = 0u;
    token_function_delta[i] = 0;
}
