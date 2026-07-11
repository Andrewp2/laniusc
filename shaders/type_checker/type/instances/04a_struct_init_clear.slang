// Clear token-indexed struct-literal expectation buffers before HIR publication.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> struct_init_field_context_instance;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;
RWStructuredBuffer<uint> struct_init_field_ordinal;
RWStructuredBuffer<uint> struct_lit_context_decl_token;
RWStructuredBuffer<uint> struct_lit_context_instance;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint PARSER_FEATURE_STRUCTS = 0x00000010u;
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
    if ((gParams.parser_feature_flags & PARSER_FEATURE_STRUCTS) == 0u)
        return;
    uint i = linear_thread_id(dtid);

    if (i < gParams.n_tokens)
    {
        struct_init_field_context_instance[i] = INVALID;
        struct_init_field_expected_ref_tag[i] = TYPE_REF_INVALID;
        struct_init_field_expected_ref_payload[i] = INVALID;
        struct_init_field_ordinal[i] = INVALID;
    }

    if (i < gParams.n_hir_nodes)
    {
        struct_lit_context_decl_token[i] = INVALID;
        struct_lit_context_instance[i] = INVALID;
    }
}
