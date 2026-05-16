// Compatibility pass for the language-name pipeline.
//
// Language symbol ids are now assigned by type_check_names_radix_03_assign_ids
// from compiler-provided symbol rows in the GPU name interner. This pass keeps
// the old pipeline slot source-free while downstream callers are migrated to the
// direct assign_ids producer.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> language_name_id;

static const uint LANGUAGE_SYMBOL_COUNT = 19u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x;
    if (i < LANGUAGE_SYMBOL_COUNT && language_name_id[i] == 0xffffffffu)
        return;
}
