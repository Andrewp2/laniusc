// Clear dense-HIR-indexed public-signature topology state.

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_child_ordinal;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_type_index_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity) return;
    interface_type_parent[node] = INVALID;
    interface_type_child_ordinal[node] = INVALID;
    interface_type_seed_owner[node] = INVALID;
    interface_type_index_by_hir[node] = INVALID;
}
