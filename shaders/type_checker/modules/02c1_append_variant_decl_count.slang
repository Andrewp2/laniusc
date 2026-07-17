// Append the compact variant family to the dense declaration table.
//
// The core declaration scan publishes its count first. This one-lane pass
// turns that count into the final concatenated declaration count before the
// variant scatter and all declaration-key consumers run.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_variant_count;
RWStructuredBuffer<uint> decl_count_out;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint core_count = min(decl_count_out[0u], gParams.n_hir_nodes);
    uint variant_count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    decl_count_out[0u] = min(core_count + variant_count, gParams.n_hir_nodes);
}
