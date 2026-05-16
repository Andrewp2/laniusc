struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> method_decl_receiver_ref_tag;
RWStructuredBuffer<uint> method_decl_receiver_ref_payload;
RWStructuredBuffer<uint> method_decl_module_id;
RWStructuredBuffer<uint> method_decl_impl_node;
RWStructuredBuffer<uint> method_decl_name_token;
RWStructuredBuffer<uint> method_decl_name_id;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> method_decl_visibility;
RWStructuredBuffer<uint> method_call_receiver_ref_tag;
RWStructuredBuffer<uint> method_call_receiver_ref_payload;
RWStructuredBuffer<uint> method_call_name_id;
RWStructuredBuffer<uint> method_call_site_module_id;

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
    if (i < gParams.n_tokens)
    {
        method_decl_receiver_ref_tag[i] = TYPE_REF_INVALID;
        method_decl_receiver_ref_payload[i] = INVALID;
        method_decl_module_id[i] = INVALID;
        method_decl_impl_node[i] = INVALID;
        method_decl_name_token[i] = INVALID;
        method_decl_name_id[i] = INVALID;
        method_decl_param_offset[i] = INVALID;
        method_decl_receiver_mode[i] = 0u;
        method_decl_visibility[i] = 0u;
        method_call_receiver_ref_tag[i] = TYPE_REF_INVALID;
        method_call_receiver_ref_payload[i] = INVALID;
        method_call_name_id[i] = INVALID;
        method_call_site_module_id[i] = INVALID;
    }
}
