struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> language_name_id;

static const uint INVALID = 0xffffffffu;
static const uint LANGUAGE_NAME_COUNT = 18u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x;
    if (i < LANGUAGE_NAME_COUNT)
        language_name_id[i] = INVALID;
}
