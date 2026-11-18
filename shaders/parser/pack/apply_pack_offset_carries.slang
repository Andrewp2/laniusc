// Applies paired block carries to packed parser stream offsets.

struct Params { uint n_pairs; uint n_blocks; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> sc_block_prefix;
StructuredBuffer<uint> emit_block_prefix;
RWStructuredBuffer<uint> sc_offsets;
RWStructuredBuffer<uint> emit_offsets;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_pairs()
{
    uint active_tokens = token_count[0u] + 2u;
    return min(gParams.n_pairs, active_tokens > 0u ? active_tokens - 1u : 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_pairs())
        return;
    uint block = row / WG_SIZE;
    if (block == 0u)
        return;
    sc_offsets[row] += sc_block_prefix[block - 1u];
    emit_offsets[row] += emit_block_prefix[block - 1u];
}
