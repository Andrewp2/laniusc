// One parallel pointer-doubling step over type-parent links.

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_root_link_in;
StructuredBuffer<uint> interface_type_root_owner_in;
RWStructuredBuffer<uint> interface_type_root_link_out;
RWStructuredBuffer<uint> interface_type_root_owner_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity)
        return;
    uint link = interface_type_root_link_in[node];
    uint owner = interface_type_root_owner_in[node];
    if (link < gParams.hir_capacity)
    {
        uint ancestor_owner = interface_type_root_owner_in[link];
        if (ancestor_owner < gParams.hir_capacity)
            owner = ancestor_owner;
        uint ancestor_link = interface_type_root_link_in[link];
        link = ancestor_link < gParams.hir_capacity ? ancestor_link : INVALID;
    }
    interface_type_root_link_out[node] = link;
    interface_type_root_owner_out[node] = owner;
}
