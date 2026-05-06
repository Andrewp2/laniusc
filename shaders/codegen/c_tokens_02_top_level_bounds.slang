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
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> token_codegen_flags;
RWStructuredBuffer<uint> codegen_bounds;

static const uint FLAG_IN_FUNCTION_ITEM = 1u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= active_token_count())
        return;

    if ((token_codegen_flags[i] & FLAG_IN_FUNCTION_ITEM) != 0u)
        return;

    uint old_value;
    InterlockedMin(codegen_bounds[0u], i, old_value);
    InterlockedMax(codegen_bounds[1u], i, old_value);
}
