struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> method_decl_receiver_type;
RWStructuredBuffer<uint> method_decl_impl_token;
RWStructuredBuffer<uint> method_decl_name_token;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_lookup_key;
RWStructuredBuffer<uint> method_lookup_receiver;
RWStructuredBuffer<uint> method_lookup_name_token;
RWStructuredBuffer<uint> method_lookup_fn;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
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
        method_decl_receiver_type[i] = TY_UNKNOWN;
        method_decl_impl_token[i] = INVALID;
        method_decl_name_token[i] = INVALID;
        method_decl_param_offset[i] = INVALID;
    }

    uint lookup_capacity = max(gParams.n_tokens * 2u, 1u);
    if (i < lookup_capacity)
    {
        method_lookup_key[i] = 0u;
        method_lookup_receiver[i] = TY_UNKNOWN;
        method_lookup_name_token[i] = INVALID;
        method_lookup_fn[i] = INVALID;
    }
}
