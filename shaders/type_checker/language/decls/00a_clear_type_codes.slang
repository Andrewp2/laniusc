struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> language_type_code_by_name_id;
RWStructuredBuffer<uint> language_entrypoint_tag_by_name_id;
RWStructuredBuffer<uint> language_intrinsic_tag_by_name_id;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 63u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;

    language_type_code_by_name_id[i] = 0u;
    language_entrypoint_tag_by_name_id[i] = 0u;
    language_intrinsic_tag_by_name_id[i] = 0u;
}
