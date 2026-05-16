// Clear token-indexed struct-literal expectation buffers before HIR publication.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> struct_init_field_context_instance;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;
RWStructuredBuffer<uint> struct_init_field_ordinal;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    struct_init_field_context_instance[i] = INVALID;
    struct_init_field_expected_ref_tag[i] = TYPE_REF_INVALID;
    struct_init_field_expected_ref_payload[i] = INVALID;
    struct_init_field_ordinal[i] = INVALID;
}
