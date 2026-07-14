// Mark reachable public-signature type nodes in reverse HIR preorder. A GPU
// scan over these flags gives descendants lower persisted indices than parents.

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> interface_type_root_owner;
StructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_type_reverse_flag;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint reverse_row = linear_thread_id(dtid);
    if (reverse_row >= gParams.hir_capacity)
        return;
    uint node = gParams.hir_capacity - 1u - reverse_row;
    uint active = min(hir_status[5u], gParams.hir_capacity);
    uint root = node < active && hir_kind[node] == HIR_TYPE
                    ? interface_type_root_owner[node]
                    : INVALID;
    interface_type_reverse_flag[reverse_row] =
        root < active && interface_type_seed_owner[root] < gParams.decl_capacity ? 1u : 0u;
}
