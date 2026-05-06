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
StructuredBuffer<int> lengths;
StructuredBuffer<int> block_prefix;
RWStructuredBuffer<uint> token_codegen_flags;

static const uint FLAG_IN_FUNCTION_ITEM = 1u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 gid: SV_GroupID)
{
    uint i = tid.x;
    if (i >= active_token_count())
        return;

    int block_base = gid.x == 0u ? 0 : block_prefix[gid.x - 1u];
    int depth = lengths[i] + block_base;
    if (depth > 0)
    {
        uint old_flags;
        InterlockedOr(token_codegen_flags[i], FLAG_IN_FUNCTION_ITEM, old_flags);
    }
}
