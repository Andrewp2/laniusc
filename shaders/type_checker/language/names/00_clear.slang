struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> language_name_id;
RWStructuredBuffer<uint> name_max_len;

static const uint INVALID = 0xffffffffu;
static const uint LANGUAGE_NAME_COUNT = 67u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x;
    if (i == 0u)
        name_max_len[0u] = 0u;
    if (i < LANGUAGE_NAME_COUNT)
        language_name_id[i] = INVALID;
}
