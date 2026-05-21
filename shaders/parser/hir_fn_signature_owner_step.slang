// Pointer-jump nearest function-signature owner values over parse-tree rows.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirFnSignatureOwner;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_fn_signature_owner_link_in;
StructuredBuffer<uint> hir_fn_signature_return_owner_in;
StructuredBuffer<uint> hir_fn_signature_function_owner_in;

RWStructuredBuffer<uint> hir_fn_signature_owner_link_out;
RWStructuredBuffer<uint> hir_fn_signature_return_owner_out;
RWStructuredBuffer<uint> hir_fn_signature_function_owner_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirFnSignatureOwner.uses_ll1 != 0u
               ? min(gHirFnSignatureOwner.n, ll1_status[5u])
               : gHirFnSignatureOwner.n;
}

bool valid_node(uint node, uint active)
{
    return node != INVALID && node < active;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint active = active_node_count();
    if (node >= active)
        return;

    uint link = hir_fn_signature_owner_link_in[node];
    uint return_owner = hir_fn_signature_return_owner_in[node];
    uint function_owner = hir_fn_signature_function_owner_in[node];

    if (valid_node(link, active))
    {
        if (return_owner == INVALID)
        {
            uint parent_return_owner = hir_fn_signature_return_owner_in[link];
            if (parent_return_owner != INVALID)
                return_owner = parent_return_owner;
        }
        if (function_owner == INVALID)
        {
            uint parent_function_owner = hir_fn_signature_function_owner_in[link];
            if (parent_function_owner != INVALID)
                function_owner = parent_function_owner;
        }

        uint parent_link = hir_fn_signature_owner_link_in[link];
        link = valid_node(parent_link, active) ? parent_link : INVALID;
    }

    hir_fn_signature_owner_link_out[node] = link;
    hir_fn_signature_return_owner_out[node] = return_owner;
    hir_fn_signature_function_owner_out[node] = function_owner;
}
